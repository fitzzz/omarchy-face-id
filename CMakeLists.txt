cmake_minimum_required(VERSION 3.24)

file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION"
    OMARCHY_FACE_ID_VERSION
    LIMIT_COUNT 1
)
string(STRIP "${OMARCHY_FACE_ID_VERSION}" OMARCHY_FACE_ID_VERSION)

project(OmarchyFaceId
    VERSION "${OMARCHY_FACE_ID_VERSION}"
    DESCRIPTION "Local biometric foundation for Omarchy"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.7 REQUIRED COMPONENTS
    Core
    DBus
    Gui
    Quick
    QuickControls2
)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GSTREAMER REQUIRED IMPORTED_TARGET
    gstreamer-1.0
    gstreamer-app-1.0
)

qt_standard_project_setup(REQUIRES 6.7)
qt_policy(SET QTP0004 NEW)

qt_add_executable(omarchy-face-id
    app/GazeClient.cpp
    app/GazeClient.h
    app/main.cpp
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
        integration/omarchy-plugin/Service.qml
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

target_compile_definitions(omarchy-face-id PRIVATE
    OMARCHY_FACE_ID_VERSION="${PROJECT_VERSION}"
)

install(TARGETS omarchy-face-id
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)
install(FILES packaging/io.omarchy.FaceId.desktop
    DESTINATION share/applications
)
install(FILES packaging/io.omarchy.FaceId.svg
    DESTINATION share/icons/hicolor/scalable/apps
)
include(CTest)
if(BUILD_TESTING)
    add_test(NAME qml-smoke COMMAND omarchy-face-id --smoke-test)
    set_tests_properties(qml-smoke PROPERTIES ENVIRONMENT
        "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
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
        "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
    )
    add_test(NAME uninstall-tty
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_uninstall_tty.sh
            $<TARGET_FILE:omarchy-face-id>
    )
    add_test(NAME camera-handoff
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_camera_handoff.sh
    )
    add_test(NAME lock-integration
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_lock_integration.sh
    )
    add_test(NAME wizard-activation
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_wizard_activation.sh
            $<TARGET_FILE:omarchy-face-id>
    )
endif()
