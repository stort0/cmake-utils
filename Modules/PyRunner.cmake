cmake_minimum_required(VERSION 3.10)

set(MATCH_WORD       "[A-Za-z0-9_]")
set(MATCH_DECIMAL    "[0-9]")
set(MATCH_WHITESPACE "[ \t\r\n]")

function (_check_dependencies)
        set(ONE_VALUE_ARGS)
        set(MULTI_VALUE_ARGS
                DEPENDENCIES)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "${MULTI_VALUE_ARGS}" ${ARGN})

        if (NOT ARGS_DEPENDENCIES)
                message(FATAL_ERROR "Missing parameters in function call to "
                                    "_check_dependencies, please report this at "
                                    "${CMAKE_UTILS_GIT_REPO}/issues.")
        endif ()

        execute_process(
                COMMAND ${Python3_EXECUTABLE} -m pip list
                OUTPUT_VARIABLE PIP_LIST)

        string(TOLOWER "${PIP_LIST}" PIP_LIST)

        set(DEPENDENCY_REGEX "^((${MATCH_WORD}|\\.)+)(:(${MATCH_DECIMAL}+)(!)?(\\.(${MATCH_DECIMAL}+))?(\\.(${MATCH_DECIMAL}+))?([^!]+)?(!)?)?$")
        foreach (DEPENDENCY ${ARGS_DEPENDENCIES})
                string(TOLOWER "${DEPENDENCY}" DEPENDENCY)

                if (NOT "${DEPENDENCY}" MATCHES ${DEPENDENCY_REGEX})
                        message(FATAL_ERROR "Invalid dependency format "
                                            "('${DEPENDENCY}').")
                endif ()

                string(REGEX MATCH ${DEPENDENCY_REGEX} _ "${DEPENDENCY}")
                set(DEPENDENCY_NAME           "${CMAKE_MATCH_1}")
                set(DEPENDENCY_VERSION        "${CMAKE_MATCH_2}")
                set(DEPENDENCY_MAJOR          "${CMAKE_MATCH_3}")
                set(DEPENDENCY_MAJOR_STRICT   "${CMAKE_MATCH_4}")
                set(DEPENDENCY_MINOR          "${CMAKE_MATCH_5}")
                set(DEPENDENCY_PATCH          "${CMAKE_MATCH_6}")
                set(DEPENDENCY_VERSION_EXTRA  "${CMAKE_MATCH_7}")
                set(DEPENDENCY_VERSION_STRICT "${CMAKE_MATCH_8}")

                if (NOT ${DEPENDENCY_VERSION})  # No version provided
                        string(REPLACE ".." "\\." FIXED_NAME "${DEPENDENCY_NAME}")
                        set(PIP_MATCH_REGEX "\n${FIXED_NAME}${MATCH_WHITESPACE}")
                        if (NOT "${PIP_LIST}" MATCHES "${PIP_MATCH_REGEX}")
                                message(FATAL_ERROR "Missing python dependency "
                                                    "'${DEPENDENCY_NAME}'.")
                        endif ()
                        continue ()
                endif ()

                set(VERSION      "${DEPENDENCY_MAJOR}${DEPENDENCY_MINOR}${DEPENDENCY_PATCH}")
                set(FULL_VERSION "${VERSION}${DEPENDENCY_VERSION_EXTRA}")

                if (${CMAKE_MATCH_4})
                        set(MAJOR_STRICT ON)
                endif ()
                if (${CMAKE_MATCH_8})
                        set(VERSION_STRICT ON)
                endif ()
                if (MAJOR_STRING AND VERSION_STRICT)
                        message(WARNING "Both major string and "
                                        "version strict provided "
                                        "using only version strict ")
                endif ()

                if (VERSION_STRICT)
                        if (NOT "${PIP_LIST}" MATCHES "\n${DEPENDENCY_NAME}${MATCH_WHITESPACE}+${FULL_VERSION}(\n|$)")
                                message(FATAL_ERROR "Dependency '${DEPENDENCY_NAME}' "
                                                    "does is not required "
                                                    "version '${FULL_VERSION}'")
                        endif ()
                        continue ()
                endif ()

                string(REGEX MATCH "\n${DEPENDENCY_NAME}${MATCH_WHITESPACE}+(((${MATCH_DECIMAL}+)(\\.${MATCH_DECIMAL}+)?(\\.${MATCH_DECIMAL}+)?)(.+)?)?(\n|$)" _ "${PIP_LIST}")
                set(PIP_VERSION "${CMAKE_MATCH_2}")
                set(PIP_MAJOR   "${CMAKE_MATCH_3}")
                if (${VERSION} VERSION_LESS ${PIP_VERSION})
                        message(FATAL_ERROR "Dependency '${DEPENDENCY_NAME}' "
                                            "does not have the required "
                                            "version '${FULL_VERSION}'")
                endif ()

                if (MAJOR_STRICT)
                        if (NOT "${DEPENDENCY_MAJOR}" STREQUAL "${PIP_MAJOR}")
                                message(FATAL_ERROR "Dependency '${DEPENDENCY_NAME}' "
                                                    "does not have the required "
                                                    "major version '${DEPENDENCY_MAJOR}'")
                        endif ()
                endif ()
        endforeach ()
endfunction ()

function (run_python_script)
        set(ONE_VALUE_ARGS
                NAME
                CWD
                MIN_PYTHON_VERSION
                MAX_PYTHON_VERSION)
        set(MULTI_VALUE_ARGS
                DEPENDENCIES
                ARGS)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "${MULTI_VALUE_ARGS}" ${ARGN})

        if (NOT ARGS_NAME)
                message(FATAL_ERROR "Missing required argument 'NAME'.")
        endif ()

        set(Python3_FIND_VIRTUALENV FIRST)
        include(FindPython3)
        find_package(Python3 COMPONENTS Interpreter)

        if (NOT Python3_FOUND)
                message(FATAL_ERROR "Python 3 not found.")
        endif ()

        if (ARGS_MIN_PYTHON_VERSION)
                if (NOT "${ARGS_MIN_PYTHON_VERSION}" MATCHES "^${MATCH_DECIMAL}+(\\.${MATCH_DECIMAL}+)?(\\.${MATCH_DECIMAL}+)?$")
                        message(FATAL_ERROR "Invalid version format: expected "
                                            "major(.minor)(.patch).")
                endif ()
                if ("${Python3_VERSION}" VERSION_LESS "${ARGS_MIN_PYTHON_VERSION}")
                        message(FATAL_ERROR "Python 3 interpreter version is less "
                                            "than required version "
                                            "'${ARGS_MIN_PYTHON_VERSION}'.")
                endif ()
        endif ()

        if (ARGS_MAX_PYTHON_VERSION)
                if (NOT "${ARGS_MAX_PYTHON_VERSION}" MATCHES "^${MATCH_DECIMAL}+(\\.${MATCH_DECIMAL}+)?(\\.${MATCH_DECIMAL}+)?$")
                        message(FATAL_ERROR "Invalid version format: expected "
                                            "major(.minor)(.patch).")
                endif ()
                if ("${Python3_VERSION}" VERSION_GREATER "${ARGS_MAX_PYTHON_VERSION}")
                        message(FATAL_ERROR "Python 3 interpreter version is higher "
                                            "than the maximum allowed version "
                                            "'${ARGS_MAX_PYTHON_VERSION}'.")
                endif ()
        endif ()

        if (ARGS_DEPENDENCIES)
               _check_dependencies(
                       DEPENDENCIES ${ARGS_DEPENDENCIES})
        endif ()

        if (ARGS_CWD)
                execute_process(
                        COMMAND ${Python3_EXECUTABLE} "${ARGS_NAME}" ${ARGS_ARGS}
                        WORKING_DIRECTORY "${ARGS_CWD}")
        else ()
                execute_process(COMMAND ${Python3_EXECUTABLE} "${ARGS_NAME}" ${ARGS_ARGS})
        endif ()
endfunction ()
