# The app's QML plugin: reading /proc and /sys, file system sizes and
# signals to processes (procfs.h), and the processes' list (processmodel.h).
add_library(sysmonitor-qml MODULE
    plugin.cpp plugin.h
    procreader.cpp procreader.h
    procfs.cpp procfs.h
    processmodel.cpp processmodel.h
)

# So the plugin can be found next to its qmldir when running from the build tree.
file(COPY qmldir DESTINATION ${CMAKE_CURRENT_BINARY_DIR})

target_link_libraries(sysmonitor-qml PRIVATE Qt6::Qml)

install(TARGETS sysmonitor-qml DESTINATION ${PLUGIN_DIR})
install(FILES qmldir DESTINATION ${PLUGIN_DIR})
