// SPDX-License-Identifier: GPL-3.0-or-later

#include <security/pam_appl.h>
#include <security/pam_ext.h>
#include <security/pam_modules.h>
#include <systemd/sd-login.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef PAM_EXTERN
#define PAM_EXTERN
#endif

__attribute__((used, visibility("default")))
const char omarchy_face_id_consent_marker[] =
    "Omarchy Face ID consent module 1";

static const char transaction_state_key[] =
    "omarchy-face-id.consent-state";

enum transaction_state { TRANSACTION_ATTEMPTED = 1, TRANSACTION_DECLINED = 2 };

static void free_conversation_responses(struct pam_response *responses,
                                        int count) {
  if (responses == NULL)
    return;
  for (int index = 0; index < count; ++index) {
    if (responses[index].resp != NULL) {
      memset(responses[index].resp, 0, strlen(responses[index].resp));
      free(responses[index].resp);
    }
  }
  free(responses);
}

static int declined_result(pam_handle_t *handle) {
  const void *item = NULL;
  sigset_t blocked;
  if (pam_get_item(handle, PAM_CONV, &item) != PAM_SUCCESS || item == NULL ||
      sigprocmask(SIG_BLOCK, NULL, &blocked) != 0 ||
      !sigismember(&blocked, SIGINT))
    return PAM_ABORT;

  const struct pam_conv *conversation = (const struct pam_conv *)item;
  if (conversation->conv == NULL || raise(SIGINT) != 0)
    return PAM_ABORT;

  const struct pam_message message = {
      .msg_style = PAM_PROMPT_ECHO_OFF,
      .msg = "",
  };
  const struct pam_message *messages[] = {&message};
  struct pam_response *responses = NULL;
  const int result = conversation->conv(1, messages, &responses,
                                        conversation->appdata_ptr);
  free_conversation_responses(responses, 1);
  return result == PAM_CONV_ERR ? PAM_AUTH_ERR : PAM_ABORT;
}

static bool has_option(int argc, const char **argv, const char *option) {
  for (int index = 0; index < argc; ++index) {
    if (strcmp(argv[index], option) == 0)
      return true;
  }
  return false;
}

static bool local_terminal(const char *tty) {
  if (tty == NULL)
    return false;
  if (strncmp(tty, "/dev/pts/", 9) == 0)
    return tty[9] != '\0' && strchr(tty + 9, '/') == NULL;
  if (strncmp(tty, "/dev/tty", 8) == 0)
    return tty[8] >= '0' && tty[8] <= '9' && tty[9] == '\0';
  return false;
}

static bool reject_session(pam_handle_t *handle, const char *reason) {
  // Deliberately omit user names, terminal numbers, session IDs, host names,
  // and environment values. The reason is enough to diagnose compatibility
  // failures without turning the authentication log into identifying data.
  pam_syslog(handle, LOG_INFO,
             "omarchy-face-id consent skipped: gate=%s", reason);
  return false;
}

static bool local_interactive_session(pam_handle_t *handle, const char *user,
                                      bool test_mode) {
  const void *service_item = NULL;
  const void *tty_item = NULL;
  const void *rhost_item = NULL;
  if (pam_get_item(handle, PAM_SERVICE, &service_item) != PAM_SUCCESS ||
      pam_get_item(handle, PAM_TTY, &tty_item) != PAM_SUCCESS ||
      pam_get_item(handle, PAM_RHOST, &rhost_item) != PAM_SUCCESS)
    return reject_session(handle, "pam-items-unavailable");

  const char *service = (const char *)service_item;
  const char *tty = (const char *)tty_item;
  const char *rhost = (const char *)rhost_item;
  if (service == NULL || strcmp(service, "sudo") != 0)
    return reject_session(handle, "unsupported-service");
  if (!local_terminal(tty))
    return reject_session(handle, "local-terminal-unavailable");
  if (rhost != NULL && rhost[0] != '\0')
    return reject_session(handle, "remote-host-present");
  if (pam_getenv(handle, "SSH_CONNECTION") != NULL ||
      pam_getenv(handle, "SSH_CLIENT") != NULL ||
      getenv("SSH_CONNECTION") != NULL || getenv("SSH_CLIENT") != NULL)
    return reject_session(handle, "remote-environment-present");

  if (test_mode) {
    const char *state = getenv("OMARCHY_FACE_ID_TEST_SESSION");
    const bool accepted = state == NULL || strcmp(state, "local") == 0 ||
                          strcmp(state, "manager-local") == 0;
    return accepted ? true : reject_session(handle, "test-session-rejected");
  }

  const struct passwd *account = getpwnam(user);
  if (account == NULL)
    return reject_session(handle, "account-unavailable");

  // Omarchy launches terminals through the per-user service manager. Those
  // processes are intentionally outside session-N.scope, so asking logind for
  // the sudo process's own session returns ENODATA. Instead require an active,
  // local login session owned by the PAM user. The terminal/rhost/SSH checks
  // above still bind the request itself to a local interactive terminal.
  char **sessions = NULL;
  const int count = sd_uid_get_sessions(account->pw_uid, 1, &sessions);
  bool accepted = false;
  for (int index = 0; index < count && !accepted; ++index) {
    char *type = NULL;
    if (sd_session_is_active(sessions[index]) > 0 &&
        sd_session_is_remote(sessions[index]) == 0 &&
        sd_session_get_type(sessions[index], &type) >= 0 &&
        (strcmp(type, "wayland") == 0 || strcmp(type, "x11") == 0 ||
         strcmp(type, "tty") == 0))
      accepted = true;
    free(type);
  }
  for (int index = 0; index < count; ++index)
    free(sessions[index]);
  free(sessions);
  return accepted ? true
                  : reject_session(handle, "active-local-session-unavailable");
}

static void release_transaction_marker(pam_handle_t *handle, void *data,
                                       int status) {
  (void)handle;
  (void)status;
  free(data);
}

static enum transaction_state transaction_state(const pam_handle_t *handle) {
  const void *marker = NULL;
  return pam_get_data(handle, transaction_state_key, &marker) == PAM_SUCCESS &&
                 marker != NULL
             ? (enum transaction_state)(*(const unsigned char *)marker)
             : 0;
}

static bool remember_transaction_state(pam_handle_t *handle,
                                       enum transaction_state state) {
  const void *existing = NULL;
  if (pam_get_data(handle, transaction_state_key, &existing) == PAM_SUCCESS &&
      existing != NULL) {
    *(unsigned char *)existing = (unsigned char)state;
    return true;
  }
  char *marker = malloc(1);
  if (marker == NULL)
    return false;

  *marker = (char)state;
  if (pam_set_data(handle, transaction_state_key, marker,
                   release_transaction_marker) != PAM_SUCCESS) {
    free(marker);
    return false;
  }
  return true;
}

static const char *helper_path(int argc, const char **argv) {
  static const char prefix[] = "helper=";
  const char *path = "/usr/libexec/omarchy-face-id-elevation";

  for (int index = 0; index < argc; ++index) {
    if (strncmp(argv[index], prefix, sizeof(prefix) - 1) == 0)
      path = argv[index] + sizeof(prefix) - 1;
  }
  return path[0] == '/' && strchr(path, '\n') == NULL ? path : NULL;
}

static char *pam_environment(const char *name, const char *value) {
  if (value == NULL)
    value = "";
  const size_t length = strlen(name) + strlen(value) + 2;
  char *entry = malloc(length);
  if (entry != NULL)
    snprintf(entry, length, "%s=%s", name, value);
  return entry;
}

static const char *session_environment(pam_handle_t *handle, const char *name) {
  const char *value = pam_getenv(handle, name);
  if (value == NULL)
    value = getenv(name);
  return value;
}

static bool valid_desktop_token(const char *value, size_t maximum_length) {
  if (value == NULL || value[0] == '\0')
    return false;

  size_t length = 0;
  for (; value[length] != '\0'; ++length) {
    const unsigned char character = (unsigned char)value[length];
    const bool valid = (character >= 'a' && character <= 'z') ||
                       (character >= 'A' && character <= 'Z') ||
                       (character >= '0' && character <= '9') ||
                       character == '.' || character == '_' ||
                       character == '-';
    if (!valid || length >= maximum_length)
      return false;
  }
  return true;
}

static const char *wayland_display(pam_handle_t *handle) {
  const char *value = session_environment(handle, "WAYLAND_DISPLAY");
  static const char prefix[] = "wayland-";
  return value != NULL && strncmp(value, prefix, sizeof(prefix) - 1) == 0 &&
                 valid_desktop_token(value + sizeof(prefix) - 1, 64)
             ? value
             : NULL;
}

static int wait_for_helper(pid_t child) {
  struct timespec pause = {.tv_sec = 0, .tv_nsec = 20 * 1000 * 1000};
  for (int elapsed_ms = 0; elapsed_ms < 80000; elapsed_ms += 20) {
    int status = 0;
    const pid_t result = waitpid(child, &status, WNOHANG);
    if (result == child) {
      if (!WIFEXITED(status))
        return 20;
      return WEXITSTATUS(status);
    }
    if (result < 0 && errno != EINTR)
      return 20;
    nanosleep(&pause, NULL);
  }

  kill(child, SIGKILL);
  while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {
  }
  return 20;
}

static bool reset_child_signals(void) {
  sigset_t empty;
  if (sigemptyset(&empty) != 0 || sigprocmask(SIG_SETMASK, &empty, NULL) != 0)
    return false;
  struct sigaction action = {0};
  action.sa_handler = SIG_DFL;
  if (sigemptyset(&action.sa_mask) != 0)
    return false;
  const int signals[] = {SIGINT, SIGTERM, SIGHUP, SIGCHLD, SIGPIPE};
  for (size_t index = 0; index < sizeof(signals) / sizeof(signals[0]); ++index) {
    if (sigaction(signals[index], &action, NULL) != 0)
      return false;
  }
  return true;
}

static bool redirect_standard_descriptors(void) {
  const int null_fd = open("/dev/null", O_RDWR | O_CLOEXEC);
  if (null_fd < 0)
    return false;
  bool ok = true;
  for (int descriptor = STDIN_FILENO; descriptor <= STDERR_FILENO;
       ++descriptor) {
    if (dup2(null_fd, descriptor) < 0)
      ok = false;
  }
  if (null_fd > STDERR_FILENO)
    close(null_fd);
  return ok;
}

static void close_other_descriptors(void) {
#ifdef SYS_close_range
  if (syscall(SYS_close_range, (unsigned int)(STDERR_FILENO + 1), UINT_MAX, 0) ==
      0)
    return;
#endif
  const long maximum = sysconf(_SC_OPEN_MAX);
  const int limit = maximum > 0 && maximum < INT_MAX ? (int)maximum : 65536;
  for (int descriptor = STDERR_FILENO + 1; descriptor < limit; ++descriptor)
    close(descriptor);
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *handle, int flags, int argc,
                                   const char **argv) {
  (void)flags;
  const enum transaction_state prior_state = transaction_state(handle);
  if (prior_state == TRANSACTION_DECLINED)
    return declined_result(handle);
  if (prior_state == TRANSACTION_ATTEMPTED)
    return PAM_IGNORE;

  const char *helper = helper_path(argc, argv);
  const char *user = NULL;
  const bool test_mode = has_option(argc, argv, "test_mode=1");
  if (helper == NULL || pam_get_user(handle, &user, NULL) != PAM_SUCCESS)
    return PAM_IGNORE;
  if (!local_interactive_session(handle, user, test_mode))
    return PAM_IGNORE;

  char *user_environment = pam_environment("PAM_USER", user);
  const char *wayland = wayland_display(handle);
  char *wayland_environment =
      wayland == NULL ? NULL : pam_environment("WAYLAND_DISPLAY", wayland);
  char *test_allow_environment =
      test_mode
          ? pam_environment("OMARCHY_FACE_ID_ELEVATION_ALLOW_UNPRIVILEGED", "1")
          : NULL;
  char *test_runtime_environment =
      test_mode
          ? pam_environment("OMARCHY_FACE_ID_ELEVATION_RUNTIME_DIR",
                            getenv("OMARCHY_FACE_ID_ELEVATION_RUNTIME_DIR"))
          : NULL;
  char *test_response_environment =
      test_mode
          ? pam_environment("OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE",
                            getenv("OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE"))
          : NULL;
  char *test_timeout_environment =
      test_mode
          ? pam_environment("OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS",
                            getenv("OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS"))
          : NULL;
  char *test_verifier_environment =
      test_mode
          ? pam_environment("OMARCHY_FACE_ID_ELEVATION_TEST_VERIFIER",
                            getenv("OMARCHY_FACE_ID_ELEVATION_TEST_VERIFIER"))
          : NULL;
  char *test_verify_result_environment =
      test_mode
          ? pam_environment("OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT",
                            getenv("OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT"))
          : NULL;
  char *test_pam_dir_environment =
      test_mode
          ? pam_environment("OMARCHY_FACE_ID_ELEVATION_TEST_PAM_DIR",
                            getenv("OMARCHY_FACE_ID_ELEVATION_TEST_PAM_DIR"))
          : NULL;
  if (user_environment == NULL ||
      (wayland != NULL && wayland_environment == NULL) ||
      (test_mode &&
       (test_allow_environment == NULL || test_runtime_environment == NULL ||
        test_response_environment == NULL ||
        test_timeout_environment == NULL || test_verifier_environment == NULL ||
        test_verify_result_environment == NULL ||
        test_pam_dir_environment == NULL))) {
    free(user_environment);
    free(wayland_environment);
    free(test_allow_environment);
    free(test_runtime_environment);
    free(test_response_environment);
    free(test_timeout_environment);
    free(test_verifier_environment);
    free(test_verify_result_environment);
    free(test_pam_dir_environment);
    return PAM_IGNORE;
  }

  if (!remember_transaction_state(handle, TRANSACTION_ATTEMPTED))
    return PAM_IGNORE;
  const pid_t child = fork();
  if (child == 0) {
    const pid_t expected_parent = getppid();
    if (!reset_child_signals() || !redirect_standard_descriptors() ||
        prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 ||
        getppid() != expected_parent || expected_parent <= 1)
      _exit(20);
    close_other_descriptors();
    char *const arguments[] = {(char *)helper, "request", NULL};
    char *environment[16];
    int environment_count = 0;
    environment[environment_count++] = user_environment;
    if (wayland_environment != NULL)
      environment[environment_count++] = wayland_environment;
    if (test_mode) {
      environment[environment_count++] = test_allow_environment;
      environment[environment_count++] = test_runtime_environment;
      environment[environment_count++] = test_response_environment;
      environment[environment_count++] = test_timeout_environment;
      environment[environment_count++] = test_verifier_environment;
      environment[environment_count++] = test_verify_result_environment;
      environment[environment_count++] = test_pam_dir_environment;
    }
    environment[environment_count++] = "PATH=/usr/bin:/bin";
    environment[environment_count++] = "LANG=C.UTF-8";
    environment[environment_count++] = "LC_ALL=C.UTF-8";
    environment[environment_count] = NULL;
    execve(helper, arguments, environment);
    _exit(20);
  }

  free(user_environment);
  free(wayland_environment);
  free(test_allow_environment);
  free(test_runtime_environment);
  free(test_response_environment);
  free(test_timeout_environment);
  free(test_verifier_environment);
  free(test_verify_result_environment);
  free(test_pam_dir_environment);
  if (child < 0)
    return PAM_IGNORE;

  const int result = wait_for_helper(child);
  if (result == 0)
    return PAM_SUCCESS;
  if (result == 10) {
    (void)remember_transaction_state(handle, TRANSACTION_DECLINED);
    return declined_result(handle);
  }
  return PAM_IGNORE;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *handle, int flags, int argc,
                              const char **argv) {
  (void)handle;
  (void)flags;
  (void)argc;
  (void)argv;
  return PAM_IGNORE;
}
