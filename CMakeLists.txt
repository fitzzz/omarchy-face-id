cmake_minimum_required(VERSION 3.24)

project(OmarchyFaceUnlock
    VERSION 0.2.0
    DESCRIPTION "Guided Gaze enrollment for Omarchy"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.7 REQUIRED COMPONENTS
    Core
    DBus
    Gui
    Multimedia
    Quick
    QuickControls2
)

qt_standard_project_setup(REQUIRES 6.7)
qt_policy(SET QTP0004 NEW)

qt_add_executable(omarchy-face-unlock
    app/GazeClient.cpp
    app/GazeClient.h
    app/main.cpp
)

qt_add_qml_module(omarchy-face-unlock
    URI FaceUnlock
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/ActionButton.qml
        qml/components/EyeIndicator.qml
        qml/components/StepRail.qml
)

target_link_libraries(omarchy-face-unlock PRIVATE
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::Multimedia
    Qt6::Quick
    Qt6::QuickControls2
)

install(TARGETS omarchy-face-unlock
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)
install(FILES packaging/io.omarchy.FaceUnlock.desktop
    DESTINATION share/applications
)
install(FILES packaging/io.omarchy.FaceUnlock.svg
    DESTINATION share/icons/hicolor/scalable/apps
)
include(CTest)
if(BUILD_TESTING)
    add_test(NAME qml-smoke COMMAND omarchy-face-unlock --smoke-test)
    set_tests_properties(qml-smoke PROPERTIES ENVIRONMENT
        "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
    )
    add_test(NAME packaging-script
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_packaging_script.sh
    )
    add_test(NAME gaze-install-script
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_gaze_install_script.sh
    )
    add_test(NAME camera-handoff
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_camera_handoff.sh
    )
endif()
