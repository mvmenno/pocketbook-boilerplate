cmake_minimum_required(VERSION 3.20)
project(hello_world C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Official InkView SDK headers (fetched by `./pb setup` into sdk/include).
set(PB_SDK_INCLUDE "${CMAKE_SOURCE_DIR}/sdk/include" CACHE PATH "InkView SDK headers")
if(NOT EXISTS "${PB_SDK_INCLUDE}/inkview.h")
    message(FATAL_ERROR "inkview.h not found in ${PB_SDK_INCLUDE} - run ./pb setup")
endif()

add_executable(hello_world.app src/main.c)
target_include_directories(hello_world.app PRIVATE "${PB_SDK_INCLUDE}")
target_compile_options(hello_world.app PRIVATE -Wall -Wextra)
target_link_libraries(hello_world.app PRIVATE inkview)

# Dev helper: launches an app as a task and brings it to the foreground
# (used by `./pb run`; also works on a real device over ssh/telnet).
add_executable(pb-launch tools/pb-launch.c)
target_include_directories(pb-launch PRIVATE "${PB_SDK_INCLUDE}")
target_link_libraries(pb-launch PRIVATE inkview)

# Release builds are stripped to keep the binary small on the device.
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    target_link_options(hello_world.app PRIVATE -s)
endif()
