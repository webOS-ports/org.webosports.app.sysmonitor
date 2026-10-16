# Unit tests for the app's C++ (SysMonitorApp/procfs.h, procreader.h,
# processmodel.h).
# See README.md.
#
# Off by default, so image builds are unaffected:
#   cmake -DBUILD_TESTING=ON ...
# It needs googletest in the sysroot.

find_package(GTest REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Test)

add_executable(sysmonitor-tests
    unit/main.cpp
    unit/test_procfs.cpp
    unit/test_procreader.cpp
    unit/test_processmodel.cpp
    ${PROJECT_SOURCE_DIR}/SysMonitorApp/procfs.cpp
    ${PROJECT_SOURCE_DIR}/SysMonitorApp/procfs.h
    ${PROJECT_SOURCE_DIR}/SysMonitorApp/procreader.cpp
    ${PROJECT_SOURCE_DIR}/SysMonitorApp/procreader.h
    ${PROJECT_SOURCE_DIR}/SysMonitorApp/processmodel.cpp
    ${PROJECT_SOURCE_DIR}/SysMonitorApp/processmodel.h
)
# The processes captured on the devices.
target_compile_definitions(sysmonitor-tests PRIVATE FIXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures")
target_include_directories(sysmonitor-tests PRIVATE ${PROJECT_SOURCE_DIR}/SysMonitorApp)
target_link_libraries(sysmonitor-tests PRIVATE GTest::gtest Qt6::Core Qt6::Test)

add_test(NAME sysmonitor-unit COMMAND sysmonitor-tests)
