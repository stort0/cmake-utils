cmake_minimum_required(VERSION 3.10)

find_package(Git)
if (NOT GIT_FOUND)
        message(FATAL_ERROR "Git is required to download cmake-utils. You can "
                            "download git at https://git-scm.com/downloads")
endif ()

if (NOT DEFINED ${CMAKE_UTILS_PATH})
        message(STATUS "No CMAKE_UTILS_PATH specified, using CMAKE_BINARY_DIR/cmake-utils")
        set(CMAKE_UTILS_PATH "${CMAKE_BINARY_DIR}/cmake-utils")
endif ()

set(CMAKE_UTILS_GIT_REPO "https://github.com/stort0/cmake-utils" CACHE STRING "cmake-utils git repository.")

if (NOT EXISTS "${CMAKE_UTILS_PATH}")
        execute_process(
                COMMAND git clone "${CMAKE_UTILS_GIT_REPO}.git"
                --quiet --branch "main" --single-branch ${CMAKE_UTILS_PATH})
else ()
        execute_process(
                COMMAND git pull --quiet
                WORKING_DIRECTORY ${CMAKE_UTILS_PATH})
endif ()

if (NOT EXISTS "${CMAKE_UTILS_PATH}")
        message(FATAL_ERROR "Error downloading cmake-utils")
endif ()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_UTILS_PATH}/Modules")
