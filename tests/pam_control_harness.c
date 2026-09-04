// SPDX-License-Identifier: GPL-3.0-or-later

#include <security/pam_appl.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int conversation_interrupted = 0;

static int respond(int count, const struct pam_message **messages,
                   struct pam_response **responses, void *data) {
  (void)data;
  if (count <= 0 || messages == NULL || responses == NULL)
    return PAM_CONV_ERR;

  sigset_t pending;
  if (sigpending(&pending) == 0 && sigismember(&pending, SIGINT)) {
    conversation_interrupted = 1;
    return PAM_CONV_ERR;
  }

  struct pam_response *answers = calloc((size_t)count, sizeof(*answers));
  if (answers == NULL)
    return PAM_BUF_ERR;

  for (int index = 0; index < count; ++index) {
    if (messages[index]->msg_style == PAM_PROMPT_ECHO_OFF ||
        messages[index]->msg_style == PAM_PROMPT_ECHO_ON) {
      answers[index].resp = strdup("password");
      if (answers[index].resp == NULL) {
        for (int prior = 0; prior < index; ++prior)
          free(answers[prior].resp);
        free(answers);
        return PAM_BUF_ERR;
      }
    }
  }
  *responses = answers;
  return PAM_SUCCESS;
}

int main(int argc, char **argv) {
  if (argc != 4 && argc != 5) {
    fprintf(stderr, "usage: %s CONFDIR SERVICE USER [ATTEMPTS]\n", argv[0]);
    return 2;
  }

  int attempts = 1;
  if (argc == 5) {
    char *end = NULL;
    const long parsed = strtol(argv[4], &end, 10);
    if (end == argv[4] || *end != '\0' || parsed < 1 || parsed > 10) {
      fprintf(stderr, "ATTEMPTS must be between 1 and 10\n");
      return 2;
    }
    attempts = (int)parsed;
  }

  const struct pam_conv conversation = {respond, NULL};
  pam_handle_t *handle = NULL;
  int result =
      pam_start_confdir(argv[2], argv[3], &conversation, argv[1], &handle);
  if (result == PAM_SUCCESS)
    result = pam_set_item(handle, PAM_RUSER, argv[3]);
  const char *session = getenv("OMARCHY_FACE_ID_TEST_SESSION");
  const char *tty =
      session != NULL && strcmp(session, "headless") == 0 ? "" : "/dev/pts/42";
  const char *rhost =
      session != NULL && strcmp(session, "ssh") == 0 ? "example.invalid" : "";
  if (result == PAM_SUCCESS)
    result = pam_set_item(handle, PAM_TTY, tty);
  if (result == PAM_SUCCESS)
    result = pam_set_item(handle, PAM_RHOST, rhost);
  if (result == PAM_SUCCESS && session != NULL && strcmp(session, "ssh") == 0)
    result = pam_putenv(handle, "SSH_CONNECTION=192.0.2.1 1 192.0.2.2 2");
  const char *runtime = getenv("OMARCHY_FACE_ID_ELEVATION_RUNTIME_DIR");
  if (result == PAM_SUCCESS && runtime != NULL) {
    const char prefix[] = "OMARCHY_FACE_ID_ELEVATION_RUNTIME_DIR=";
    const size_t setting_length = strlen(prefix) + strlen(runtime) + 1;
    char *setting = malloc(setting_length);
    if (setting == NULL)
      result = PAM_BUF_ERR;
    else {
      snprintf(setting, setting_length, "%s%s", prefix, runtime);
      result = pam_putenv(handle, setting);
      free(setting);
    }
  }
  int authentication_calls = 0;
  int authentication_cancelled = 0;
  sigset_t interrupt_set;
  sigset_t previous_mask;
  sigemptyset(&interrupt_set);
  sigaddset(&interrupt_set, SIGINT);
  const int mask_result = sigprocmask(SIG_BLOCK, &interrupt_set, &previous_mask);
  if (result == PAM_SUCCESS && mask_result != 0)
    result = PAM_SYSTEM_ERR;
  if (result == PAM_SUCCESS) {
    for (int attempt = 0; attempt < attempts; ++attempt) {
      result = pam_authenticate(handle, 0);
      authentication_calls++;
      sigset_t pending;
      if (sigpending(&pending) == 0 && sigismember(&pending, SIGINT)) {
        authentication_cancelled = 1;
        break;
      }
      if (result != PAM_AUTH_ERR && result != PAM_AUTHINFO_UNAVAIL &&
          result != PAM_MAXTRIES && result != PAM_PERM_DENIED)
        break;
    }
  }
  if (authentication_cancelled) {
    const struct timespec no_wait = {0, 0};
    (void)sigtimedwait(&interrupt_set, NULL, &no_wait);
  }
  if (mask_result == 0)
    (void)sigprocmask(SIG_SETMASK, &previous_mask, NULL);
  if (handle != NULL)
    pam_end(handle, result);

  printf("pam_result=%d\n", result);
  printf("pam_calls=%d\n", authentication_calls);
  printf("pam_cancelled=%d\n", authentication_cancelled);
  printf("pam_conversation_interrupted=%d\n", conversation_interrupted);
  printf("sudo_counted_attempts=%d\n",
         conversation_interrupted ? authentication_calls - 1
                                  : authentication_calls);
  return result == PAM_SUCCESS ? 0 : 1;
}
