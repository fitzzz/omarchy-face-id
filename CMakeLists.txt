cmake_minimum_required(VERSION 3.24)

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION"
    OMARCHY_FACE_ID_VERSION
    LIMIT_COUNT 1
)
string(STRIP "${OMARCHY_FACE_ID_VERSION}" OMARCHY_FACE_ID_VERSION)

project(OmarchyFaceId
    VERSION "${OMARCHY_FACE_ID_VERSION}"
    DESCRIPTION "Local biometric foundation for Omarchy"
    LANGUAGES C CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.7 REQUIRED COMPONENTS
    Core
    DBus
    Gui
    Network
    Qml
    Quick
    QuickControls2
)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GSTREAMER REQUIRED IMPORTED_TARGET
    gstreamer-1.0
    gstreamer-app-1.0
)
pkg_check_modules(SYSTEMD REQUIRED IMPORTED_TARGET libsystemd)
find_library(PAM_LIBRARY pam REQUIRED)

qt_standard_project_setup(REQUIRES 6.7)
qt_policy(SET QTP0004 NEW)

qt_add_executable(omarchy-face-id
    app/CameraInventory.cpp
    app/CameraInventory.h
    app/DiagnosticLog.cpp
    app/DiagnosticLog.h
    app/GazeClient.cpp
    app/GazeClient.h
    app/OmarchyTheme.cpp
    app/OmarchyTheme.h
    app/main.cpp
)

qt_add_executable(omarchy-face-id-presence
    presence/main.cpp
    app/DiagnosticLog.cpp
    app/DiagnosticLog.h
)

qt_add_executable(omarchy-face-id-elevation
    elevation/main.cpp
    app/DiagnosticLog.cpp
    app/DiagnosticLog.h
    app/OmarchyTheme.cpp
    app/OmarchyTheme.h
)
# This target embeds a closed QML surface and deliberately does not use the
# repository-wide import scan, which would also discover the separate
# Quickshell plugin sources. The focused import test below scans only the
# elevation surface and its embedded components.
set_target_properties(omarchy-face-id-elevation PROPERTIES
    QT_QML_MODULE_NO_IMPORT_SCAN TRUE
)

qt_add_resources(omarchy-face-id-elevation "elevation_prompt"
    PREFIX "/elevation"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/elevation"
    FILES
        elevation/ConsentPrompt.qml
)

qt_add_resources(omarchy-face-id-elevation "elevation_components"
    PREFIX "/elevation"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/qml/components"
    FILES
        qml/components/ActionButton.qml
        qml/components/FaceScanIndicator.qml
)

add_library(pam-omarchy-face-id-consent MODULE
    elevation/pam_consent.c
)
set_target_properties(pam-omarchy-face-id-consent PROPERTIES
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
    PREFIX ""
    OUTPUT_NAME "pam_omarchy_face_id_consent"
)
target_link_libraries(pam-omarchy-face-id-consent PRIVATE
    ${PAM_LIBRARY}
    PkgConfig::SYSTEMD
)

qt_add_qml_module(omarchy-face-id
    URI FaceId
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/ActionButton.qml
        qml/components/EyeIndicator.qml
        qml/components/FaceScanIndicator.qml
        qml/components/OmarchyWordmark.qml
        qml/components/StepRail.qml
)

qt_add_resources(omarchy-face-id "face_id_integration"
    PREFIX "/"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}"
    FILES
        assets/ding.mp3
        config/default-config.toml
        integration/omarchy-plugin/FaceIdIndicator.qml
        integration/omarchy-plugin/LockState.js
        integration/omarchy-plugin/Service.qml
        integration/omarchy-plugin/log-event.sh
        integration/omarchy-plugin/manifest.json
        packaging/pam/omarchy-face-id-lock
        scripts/install-gaze-arch.sh
        scripts/uninstall.sh
)

target_link_libraries(omarchy-face-id PRIVATE
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    PkgConfig::GSTREAMER
)

target_link_libraries(omarchy-face-id-presence PRIVATE
    Qt6::Core
    PkgConfig::GSTREAMER
)
target_link_libraries(omarchy-face-id-elevation PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    ${PAM_LIBRARY}
)
target_include_directories(omarchy-face-id-elevation PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/app
)
target_include_directories(omarchy-face-id-presence PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/app
)

target_compile_definitions(omarchy-face-id PRIVATE
    OMARCHY_FACE_ID_VERSION="${PROJECT_VERSION}"
)

install(TARGETS omarchy-face-id
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)
install(TARGETS omarchy-face-id-presence
    RUNTIME DESTINATION libexec
)
install(TARGETS omarchy-face-id-elevation
    RUNTIME DESTINATION libexec
)
install(TARGETS pam-omarchy-face-id-consent
    LIBRARY DESTINATION lib/security
)
install(PROGRAMS
    scripts/install-gaze-arch.sh
    scripts/uninstall.sh
    DESTINATION share/omarchy-face-id
)
install(FILES packaging/io.omarchy.FaceId.desktop
    DESTINATION share/applications
)
install(FILES packaging/io.omarchy.FaceId.svg
    DESTINATION share/icons/hicolor/scalable/apps
)
include(CTest)
if(BUILD_TESTING)
    add_executable(omarchy-face-id-pam-harness
        tests/pam_control_harness.c
    )
    target_link_libraries(omarchy-face-id-pam-harness PRIVATE ${PAM_LIBRARY})

    add_executable(omarchy-face-id-lock-state-harness
        tests/lock_state_harness.cpp
    )
    target_link_libraries(omarchy-face-id-lock-state-harness PRIVATE
        Qt6::Core
        Qt6::Qml
    )

    add_test(NAME qml-smoke COMMAND omarchy-face-id --smoke-test)
    set_tests_properties(qml-smoke PROPERTIES ENVIRONMENT
        "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;OMARCHY_FACE_ID_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/test-config;XDG_STATE_HOME=${CMAKE_CURRENT_BINARY_DIR}/test-state"
    )
    add_test(NAME packaging-script
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_packaging_script.sh
    )
    add_test(NAME gaze-install-script
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_gaze_install_script.sh
    )
    add_test(NAME uninstall-script
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_uninstall_script.sh
    )
    add_test(NAME uninstall-cli COMMAND omarchy-face-id --uninstall --help)
    set_tests_properties(uninstall-cli PROPERTIES ENVIRONMENT
        "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;OMARCHY_FACE_ID_UNINSTALLER_PATH=${CMAKE_CURRENT_SOURCE_DIR}/scripts/uninstall.sh;OMARCHY_FACE_ID_UNINSTALLER_TEST_MODE=1"
    )
    add_test(NAME uninstall-tty
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_uninstall_tty.sh
            $<TARGET_FILE:omarchy-face-id>
            ${CMAKE_CURRENT_SOURCE_DIR}/scripts/uninstall.sh
    )
    add_test(NAME camera-handoff
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_camera_handoff.sh
    )
    add_test(NAME diagnostics-log
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_diagnostics_log.sh
            $<TARGET_FILE:omarchy-face-id>
    )
    add_test(NAME user-config
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_user_config.sh
            $<TARGET_FILE:omarchy-face-id>
    )
    add_test(NAME presence-watcher
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_presence_watcher.sh
            $<TARGET_FILE:omarchy-face-id-presence>
    )
    add_test(NAME elevation-bridge
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_elevation_bridge.sh
            $<TARGET_FILE:omarchy-face-id-elevation>
    )
    add_test(NAME elevation-verifier
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_elevation_verifier.sh
            $<TARGET_FILE:omarchy-face-id-elevation>
    )
    add_test(NAME elevation-qml-imports
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_elevation_qml_imports.sh
    )
    add_test(NAME sudo-pam-flow
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_sudo_pam_flow.sh
            $<TARGET_FILE:omarchy-face-id-pam-harness>
            $<TARGET_FILE:omarchy-face-id-elevation>
            $<TARGET_FILE:pam-omarchy-face-id-consent>
    )
    add_test(NAME lock-integration
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_lock_integration.sh
    )
    add_test(NAME lock-state
        COMMAND omarchy-face-id-lock-state-harness
            ${CMAKE_CURRENT_SOURCE_DIR}/integration/omarchy-plugin/LockState.js
    )
    add_test(NAME wizard-activation
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_wizard_activation.sh
            $<TARGET_FILE:omarchy-face-id>
    )
    add_test(NAME quiet-upgrade
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_quiet_upgrade.sh
            $<TARGET_FILE:omarchy-face-id>
    )
endif()
