cmake_minimum_required(VERSION 3.10)

set(GET_PROJECT_REPO_URL "https://github.com/stort0/cmake-utils")

# The GetProject output directory is the place where all downloaded libraries
# will be placed.
if (DEFINED GET_PROJECT_OUTPUT_DIR AND NOT DEFINED ENV{GET_PROJECT_OUTPUT_DIR})
        set(ENV{GET_PROJECT_OUTPUT_DIR} "${GET_PROJECT_OUTPUT_DIR}")
endif ()
if (NOT DEFINED ENV{GET_PROJECT_OUTPUT_DIR})
        set(ENV{GET_PROJECT_OUTPUT_DIR} "${CMAKE_HOME_DIRECTORY}/libs")
endif ()
if (NOT EXISTS $ENV{GET_PROJECT_OUTPUT_DIR})
        file(MAKE_DIRECTORY $ENV{GET_PROJECT_OUTPUT_DIR})
endif ()

# The GetProject internal directory is where the download cache is stored.
if (DEFINED INTERNAL_GET_PROJECT_DIR AND NOT DEFINED ENV{INTERNAL_GET_PROJECT_DIR})
        set(ENV{INTERNAL_GET_PROJECT_DIR} "${INTERNAL_GET_PROJECT_DIR}")
endif ()
if (NOT DEFINED ENV{INTERNAL_GET_PROJECT_DIR})
        set(ENV{INTERNAL_GET_PROJECT_DIR} "$ENV{GET_PROJECT_OUTPUT_DIR}/.GetProject")
endif ()
if (NOT EXISTS $ENV{INTERNAL_GET_PROJECT_DIR})
        file(MAKE_DIRECTORY $ENV{INTERNAL_GET_PROJECT_DIR})
endif ()

# The GetProject internal build directory is where libraries build artifacts are
# stored.
if (DEFINED INTERNAL_BUILD_GET_PROJECT_DIR AND NOT DEFINED ENV{INTERNAL_BUILD_GET_PROJECT_DIR})
        set(ENV{INTERNAL_BUILD_GET_PROJECT_DIR} "${INTERNAL_BUILD_GET_PROJECT_DIR}")
endif ()
if (NOT DEFINED ENV{INTERNAL_BUILD_GET_PROJECT_DIR})
        set(ENV{INTERNAL_BUILD_GET_PROJECT_DIR} "${CMAKE_BINARY_DIR}/.GetProject")
endif ()
if (NOT EXISTS $ENV{INTERNAL_BUILD_GET_PROJECT_DIR})
        file(MAKE_DIRECTORY $ENV{INTERNAL_BUILD_GET_PROJECT_DIR})
endif ()

# ----------------------------------------------------------------------------------------------------------------------
# HELPER FUNCTIONS
# ----------------------------------------------------------------------------------------------------------------------

function (_validate_args)
        set(ONE_VALUE_ARGS
                URL
                GIT_REPOSITORY
                FILE
                LIBRARY_NAME
                INSTALL_ENABLED
                DOWNLOAD_ONLY
                BRANCH
                KEEP_UPDATED
                VERSION)
        set(MULTI_VALUE_ARGS
                OPTIONS)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "${MULTI_VALUE_ARGS}" ${ARGN})

        if (NOT ARGS_URL AND NOT ARGS_GIT_REPOSITORY)
                message(FATAL_ERROR "Either an URL or a GIT_REPOSITORY is required "
                                    "for get_project to do something.")
        endif ()

        if (ARGS_GIT_REPOSITORY AND ARGS_URL)
                message(FATAL_ERROR "Only one of GIT_REPOSITORY, ARGS_URL and "
                                    "must be set.")
        endif ()

        if (ARGS_URL AND NOT ARGS_LIBRARY_NAME)
                message(FATAL_ERROR "LIBRARY_NAME is required when not passing a "
                                    "git repository.")
        endif ()

        if (ARGS_FILE AND NOT ARGS_URL)
                message(FATAL_ERROR "FILE boolean argument must be used along URL")
        endif ()

        if (NOT ARGS_BRANCH AND ARGS_KEEP_UPDATED)
                message(WARNING "KEEP_UPDATED argument is only used when the "
                                "BRANCH argument is passed.")
        endif ()

        if (ARGS_BRANCH AND ARGS_VERSION)
                message(WARNING "VERSION argument is only used when downloading "
                                "a release, not a specific branch.")
        endif ()

        if (ARGS_DOWNLOAD_ONLY AND ARGS_OPTIONS)
                message(WARNING "OPTIONS argument is only used when the DOWNLOAD_ONLY "
                                "argument is set to OFF.")
        endif ()

        if (ARGS_GIT_REPOSITORY AND NOT ARGS_BRANCH AND NOT ARGS_VERSION)
                message(WARNING "VERSION and BRANCH argument is missing, downloading "
                                "latest public release...")
        endif ()

        if (ARGS_FILE AND ARGS_INSTALL_ENABLED)
                message(WARNING "INSTALL_ENABLED argument is only used when the FILE "
                                "argument is set to OFF.")
        endif ()
endfunction ()

function (_get_latest_tag_fallback)
        set(ONE_VALUE_ARGS
                GIT_REPOSITORY
                LIBRARY_NAME
                CLEAR
                BRANCH
                OUTPUT_VARIABLE)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_GIT_REPOSITORY OR NOT ARGS_LIBRARY_NAME)
                message(FATAL_ERROR "Missing parameters in function call to "
                                    "_get_latest_tag_fallback, please report this at "
                                    "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        # Directories
        set(INTERNAL_LIBRARY_DIR "$ENV{INTERNAL_GET_PROJECT_DIR}/${ARGS_LIBRARY_NAME}")
        set(CACHE_DIR            "${INTERNAL_LIBRARY_DIR}/get_latest_tag")
        set(GIT_DIR              "${CACHE_DIR}/.git")

        # Commands
        set(GIT_CLONE_COMMAND git clone ${ARGS_GIT_REPOSITORY}
                --no-checkout
                --depth=1
                --quiet
                ${CACHE_DIR})
        set(GIT_FETCH_TAGS git fetch
                --tags
                --depth=1
                --quiet)
        set(GIT_FETCH_COMMITS git fetch
                --depth=1
                origin ${ARGS_BRANCH}
                --quiet)
        set(GIT_COMMIT_COMMAND git rev-parse
                origin/${ARGS_BRANCH})
        set(GIT_SORT_COMMAND git for-each-ref
                --sort=-creatordate
                --format "%(refname:short)"
                refs/tags)

        if (NOT EXISTS ${CACHE_DIR})
                file(MAKE_DIRECTORY ${CACHE_DIR})

                # Clone repo with lowest depth possible and fetch tags, two
                # commands are needed as cmake does not wait for the first
                # command to finish execution before calling the second one.
                execute_process(
                        COMMAND ${GIT_CLONE_COMMAND}
                        OUTPUT_QUIET
                        ERROR_QUIET)
        endif ()

        execute_process(
                COMMAND           ${GIT_FETCH_TAGS}
                WORKING_DIRECTORY ${GIT_DIR}
                OUTPUT_QUIET
                ERROR_QUIET)

        if (ARGS_BRANCH)
                execute_process(
                        COMMAND           ${GIT_FETCH_COMMITS}
                        WORKING_DIRECTORY ${GIT_DIR}
                        OUTPUT_QUIET
                        ERROR_QUIET)
                execute_process(
                        COMMAND           ${GIT_COMMIT_COMMAND}
                        WORKING_DIRECTORY ${GIT_DIR}
                        OUTPUT_VARIABLE   COMMIT_HASH
                        OUTPUT_STRIP_TRAILING_WHITESPACE)

                if (ARGS_CLEAR)
                        file(REMOVE_RECURSE ${CACHE_DIR})
                endif ()

                if (NOT COMMIT_HASH)
                        message(FATAL_ERROR "Error obtaining latest commit for "
                                            "library '${ARGS_LIBRARY_NAME}'.")
                endif ()

                set(${ARGS_OUTPUT_VARIABLE} ${COMMIT_HASH} PARENT_SCOPE)
                return()
        endif ()

        # Sort tags by creation date
        execute_process(
                COMMAND           ${GIT_SORT_COMMAND}
                WORKING_DIRECTORY ${GIT_DIR}
                OUTPUT_VARIABLE   TAG_LIST
                OUTPUT_STRIP_TRAILING_WHITESPACE)

        if (ARGS_CLEAR)
                file(REMOVE_RECURSE ${CACHE_DIR})
        endif ()

        if (NOT TAG_LIST)
                message(FATAL_ERROR "Failed to obtain tag list.")
        endif ()

        # Get the latest tag from the tag list
        string(REGEX MATCH "([^ \n]+)" TAG_NAME ${TAG_LIST})
        set(TAG_NAME "${CMAKE_MATCH_1}")

        set(${ARGS_OUTPUT_VARIABLE} ${TAG_NAME} PARENT_SCOPE)
endfunction ()

function (_get_latest_tag_gh)
        set(ONE_VALUE_ARGS
                GIT_REPOSITORY
                LIBRARY_AUTHOR
                LIBRARY_NAME
                CLEAR
                BRANCH
                OUTPUT_VARIABLE)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_GIT_REPOSITORY OR NOT ARGS_LIBRARY_NAME)
                message(FATAL_ERROR "Missing parameters in function call to "
                                    "_get_latest_tag_gh, please report this at "
                                    "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        set(INTERNAL_LIBRARY_DIR "$ENV{INTERNAL_GET_PROJECT_DIR}/${ARGS_LIBRARY_NAME}")
        set(TMP_FILE             "${INTERNAL_LIBRARY_DIR}/github.json")
        if (NOT ARGS_BRANCH)
                set(API_URL      "https://api.github.com/repos/${ARGS_LIBRARY_AUTHOR}/${ARGS_LIBRARY_NAME}/releases/latest")
        else ()
                set(API_URL      "https://api.github.com/repos/${ARGS_LIBRARY_AUTHOR}/${ARGS_LIBRARY_NAME}/commits/${ARGS_BRANCH}")
        endif ()
        file(DOWNLOAD ${API_URL} ${TMP_FILE} STATUS RESPONSE)

        list(GET RESPONSE 0 STATUS_CODE)
        list(GET RESPONSE 1 STATUS_STRING)
        if (${STATUS_CODE} EQUAL 0)
                file(READ "${TMP_FILE}" API_RESPONSE)
                if (NOT ARGS_BRANCH)
                        string(JSON VERSION GET "${API_RESPONSE}" "tag_name")
                else ()
                        string(JSON VERSION GET "${API_RESPONSE}" "sha")
                endif ()
                set(${ARGS_OUTPUT_VARIABLE} ${VERSION} PARENT_SCOPE)
        endif ()

        if (NOT ${STATUS_CODE} EQUAL 0)
                message(STATUS "GetProject: Error using github API, using pure "
                               "git fallback to retrieve the latest tag/commit (slower).")
        endif ()

        file(REMOVE "${TMP_FILE}")
endfunction ()

function (_get_latest_tag)
        set(ONE_VALUE_ARGS
                GIT_REPOSITORY
                LIBRARY_AUTHOR
                LIBRARY_NAME
                CLEAR
                BRANCH
                OUTPUT_VARIABLE)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_GIT_REPOSITORY OR NOT ARGS_LIBRARY_NAME)
                message(FATAL_ERROR "Missing parameters in function call to "
                                    "_get_latest_tag, please report this at "
                                    "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        if ("${ARGS_GIT_REPOSITORY}" MATCHES ".*github\\.com")
                _get_latest_tag_gh(
                        GIT_REPOSITORY  ${ARGS_GIT_REPOSITORY}
                        LIBRARY_AUTHOR  ${ARGS_LIBRARY_AUTHOR}
                        LIBRARY_NAME    ${ARGS_LIBRARY_NAME}
                        CLEAR           ${ARGS_CLEAR}
                        BRANCH          ${ARGS_BRANCH}
                        OUTPUT_VARIABLE RESULT)

                if (RESULT)
                        set(${ARGS_OUTPUT_VARIABLE} ${RESULT} PARENT_SCOPE)
                        return()
                endif ()
        endif ()

        _get_latest_tag_fallback(
                GIT_REPOSITORY  ${ARGS_GIT_REPOSITORY}
                LIBRARY_NAME    ${ARGS_LIBRARY_NAME}
                CLEAR           ${ARGS_CLEAR}
                BRANCH          ${ARGS_BRANCH}
                OUTPUT_VARIABLE RESULT)

        set(${ARGS_OUTPUT_VARIABLE} ${RESULT} PARENT_SCOPE)
endfunction ()

function (_get_current_version)
        set(ONE_VALUE_ARGS
                BRANCH
                DIRECTORY
                OUTPUT_FOUND
                OUTPUT_VARIABLE)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_DIRECTORY OR NOT ARGS_OUTPUT_FOUND)
                message(FATAL_ERROR "Missing parameters in function call to "
                                    "_get_current_version, please report this at "
                                    "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        set(${OUTPUT_FOUND} OFF PARENT_SCOPE)

        if (NOT ARGS_BRANCH)
                set(GIT_COMMAND git describe --tags --exact-match)
        else ()
                set(GIT_COMMAND git rev-parse origin/${ARGS_BRANCH})
        endif ()

        execute_process(
                COMMAND           ${GIT_COMMAND}
                RESULT_VARIABLE   RESULT
                OUTPUT_VARIABLE   OUTPUT
                WORKING_DIRECTORY "${ARGS_DIRECTORY}"
                ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE)

        if ("${RESULT}" EQUAL "0")
                set(${ARGS_OUTPUT_VARIABLE} "${OUTPUT}" PARENT_SCOPE)
                set(${ARGS_OUTPUT_FOUND} ON PARENT_SCOPE)
        endif ()
endfunction ()

function (_error)
        file(REMOVE "${LOCK_FILE}")  # Defined from outside scope
        string(JOIN "" JOINED ${ARGN})
        message(FATAL_ERROR "${JOINED}")
endfunction()

function (_clear_if_necessary)
        set(ONE_VALUE_ARGS
                LIBRARY_NAME
                LIBRARY_DIR
                VERSION
                BRANCH
                OUTPUT_SHOULD_SKIP_DOWNLOAD)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_LIBRARY_NAME OR NOT ARGS_LIBRARY_DIR OR NOT ARGS_VERSION)
                _error("Missing parameters in function call to "
                       "_clear_if_necessary, please report this at "
                       "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        set(${OUTPUT_SHOULD_SKIP_DOWNLOAD} ON PARENT_SCOPE)

        if (EXISTS ${ARGS_LIBRARY_DIR})
                _get_current_version(
                        BRANCH          ${ARGS_BRANCH}
                        DIRECTORY       ${ARGS_LIBRARY_DIR}
                        OUTPUT_FOUND    VERSION_FOUND
                        OUTPUT_VARIABLE EXISTENT_VERSION)
        endif ()

        if ("${EXISTENT_VERSION}" STREQUAL "")
                set(${ARGS_OUTPUT_SHOULD_SKIP_DOWNLOAD} OFF PARENT_SCOPE)
                if (EXISTS ${ARGS_LIBRARY_DIR})
                        file(REMOVE_RECURSE ${ARGS_LIBRARY_DIR})
                endif ()
        elseif (ARGS_BRANCH)
                # If the BRANCH option is used, then the version is the commit
                # hash.
                if (${ARGS_VERSION} STREQUAL ${EXISTENT_VERSION})
                        return()
                endif ()

                set(${ARGS_OUTPUT_SHOULD_SKIP_DOWNLOAD} OFF PARENT_SCOPE)
                if (EXISTS ${ARGS_LIBRARY_DIR})
                        file(REMOVE_RECURSE ${ARGS_LIBRARY_DIR})
                endif ()
        else ()
                _check_version_collisions(
                        EXISTENT_VERSION            ${EXISTENT_VERSION}
                        NEW_VERSION                 ${ARGS_VERSION}
                        OUTPUT_SHOULD_CLEAR         SHOULD_CLEAR
                        OUTPUT_SHOULD_SKIP_DOWNLOAD SHOULD_SKIP_DOWNLOAD)

                _is_directory_empty(
                        LIBRARY_DIR     ${ARGS_LIBRARY_DIR}
                        OUTPUT_VARIABLE LIBRARY_DIR_EMPTY)

                if (SHOULD_CLEAR OR LIBRARY_DIR_EMPTY)
                        set(${ARGS_OUTPUT_SHOULD_SKIP_DOWNLOAD} OFF PARENT_SCOPE)
                        if (EXISTS ${ARGS_LIBRARY_DIR})
                                file(REMOVE_RECURSE ${ARGS_LIBRARY_DIR})
                        endif ()
                endif ()
        endif ()
endfunction ()

function (_download_file)
        set(ONE_VALUE_ARGS
                URL
                DIRECTORY
                HASH
                HASH_TYPE
                OUTPUT_HASH)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_URL OR NOT ARGS_DIRECTORY)
                _error("Missing parameters in function call to "
                       "_download_file, please report this at "
                       "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        get_filename_component(FILE_NAME ${ARGS_URL} NAME)

        set(FILE_PATH "${ARGS_DIRECTORY}/${FILE_NAME}")

        if (ARGS_HASH)
                if (NOT ARGS_HASH_TYPE)
                        _error("HASH_TYPE must be provided when "
                               "passing HASH parameter to "
                               "download_file_from_url.")
                endif ()

                file(DOWNLOAD ${ARGS_URL} ${FILE_PATH}
                        STATUS RESPONSE)
        else ()
                file(DOWNLOAD ${ARGS_URL} ${FILE_PATH}
                        STATUS RESPONSE)
        endif ()

        if (NOT RESPONSE EQUAL 0)
                list(GET RESPONSE 0 CODE)
                list(GET RESPONSE 1 RESPONSE)
                string(REGEX REPLACE "^\"(.+)\"$" "\n\\1\n" RESPONSE ${RESPONSE})
                _error("Failed to download file '${FILE_NAME}', "
                       "response {${CODE}}:${RESPONSE}")
        endif()

        file(MD5 ${FILE_PATH} NEW_HASH)
        set(${ARGS_OUTPUT_HASH} ${NEW_HASH} PARENT_SCOPE)
endfunction ()

function (_extract_archive)
        set(ONE_VALUE_ARGS
                LIBRARY_NAME)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_LIBRARY_NAME)
                _error("Missing parameters in function call to "
                       "_extract_archive, please report this at "
                       "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        # Directories and files
        set(INTERNAL_LIBRARY_DIR "$ENV{INTERNAL_GET_PROJECT_DIR}/${ARGS_LIBRARY_NAME}")
        set(TMP_DIR              "${INTERNAL_LIBRARY_DIR}/.tmp")
        set(LIBRARY_DIR          "$ENV{GET_PROJECT_OUTPUT_DIR}/${ARGS_LIBRARY_NAME}")

        # Create temporary directory and extract archive there
        file(MAKE_DIRECTORY ${TMP_DIR})
        file(ARCHIVE_EXTRACT INPUT ${FILE_PATH} DESTINATION ${TMP_DIR})

        # Move the extracted content to library directory
        file(GLOB EXTRACTED_CONTENT "${TMP_DIR}/*/**")
        file(COPY ${EXTRACTED_CONTENT} DESTINATION ${LIBRARY_DIR})

        # Clean up the temporary directory
        file(REMOVE_RECURSE ${TMP_DIR})
endfunction ()

function (_is_directory_empty)
        set(ONE_VALUE_ARGS
                LIBRARY_DIR
                OUTPUT_VARIABLE)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_LIBRARY_DIR)
                _error("Missing parameters in function call to "
                       "_is_directory_empty, please report this at "
                       "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        # Used to check if directory is empty
        file(GLOB RESULT "${ARGS_LIBRARY_DIR}/**")
        list(LENGTH RESULT FILE_COUNT)

        # If library directory exists and it's not empty
        if (NOT EXISTS ${ARGS_LIBRARY_DIR} OR ${FILE_COUNT} EQUAL 0)
                set(${ARGS_OUTPUT_VARIABLE} ON PARENT_SCOPE)
        else ()
                set(${ARGS_OUTPUT_VARIABLE} OFF PARENT_SCOPE)
        endif ()
endfunction ()

function (_check_version_collisions)
        set(ONE_VALUE_ARGS
                EXISTENT_VERSION
                NEW_VERSION
                OUTPUT_SHOULD_CLEAR
                OUTPUT_SHOULD_SKIP_DOWNLOAD)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_EXISTENT_VERSION OR NOT ARGS_NEW_VERSION)
                _error("Missing parameters in function call to "
                       "_check_version_collisions, please report this at "
                       "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        set(REGEX_VERSION "^v?(([0-9]+)(\\.([0-9]+))?(\\.([0-9]+))?)(-[a-zA-Z_0-9]+)?$")
        if (NOT ${NEW_VERSION} MATCHES ${REGEX_VERSION})
                message(WARNING "Could not get version from the tag '${NEW_VERSION}'.")
                set(${OUTPUT_SHOULD_CLEAR} ON PARENT_SCOPE)
                return()
        endif ()

        string(REGEX MATCH ${REGEX_VERSION} MATCH ${ARGS_EXISTENT_VERSION})
        set(EXISTENT_VERSION_FULL "${CMAKE_MATCH_1}${CMAKE_MATCH_7}")
        set(EXISTENT_VERSION      ${CMAKE_MATCH_1})
        set(EXISTENT_MAJOR        ${CMAKE_MATCH_2})
        set(EXISTENT_MINOR        ${CMAKE_MATCH_4})
        set(EXISTENT_PATCH        ${CMAKE_MATCH_6})

        string(REGEX MATCH ${REGEX_VERSION} MATCH ${ARGS_NEW_VERSION})
        set(NEW_VERSION_FULL "${CMAKE_MATCH_1}${CMAKE_MATCH_7}")
        set(NEW_VERSION      ${CMAKE_MATCH_1})
        set(NEW_MAJOR        ${CMAKE_MATCH_2})
        set(NEW_MINOR        ${CMAKE_MATCH_4})
        set(NEW_PATCH        ${CMAKE_MATCH_6})

        if ("${EXISTENT_VERSION}" VERSION_EQUAL "${NEW_VERSION}")
                set(${ARGS_OUTPUT_SHOULD_SKIP_DOWNLOAD} ON PARENT_SCOPE)
                return()
        endif ()

        if ("${EXISTENT_VERSION}" VERSION_GREATER "${NEW_VERSION}")
                if (NOT "${PREVIOUS_MAJOR}" STREQUAL "${CURRENT_MAJOR}")
                        message(WARNING "${ARGS_LIBRARY_NAME} requires the "
                                        "version '${NEW_VERSION_FULL}', which is "
                                        "older than the currently used one "
                                        "(${EXISTENT_VERSION_FULL}) and is "
                                        "missing a major update.")
                endif ()

                # If the already present version is greater
                # than the requested one, do nothing.
                set(${ARGS_OUTPUT_SHOULD_SKIP_DOWNLOAD} ON PARENT_SCOPE)
        else ()
                if (NOT "${PREVIOUS_MAJOR}" STREQUAL "${CURRENT_MAJOR}")
                        message(WARNING "${ARGS_LIBRARY_NAME} requires the "
                                        "version '${NEW_VERSION_FULL}', which is "
                                        "newer than the currently used one "
                                        "(${EXISTENT_VERSION_FULL}), which is "
                                        "missing a major update.")
                endif ()

                set(${ARGS_OUTPUT_SHOULD_CLEAR} ON PARENT_SCOPE)
        endif ()
endfunction ()

function (_download_library_url)
        set(ONE_VALUE_ARGS
                URL
                LIBRARY_NAME)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_URL OR NOT ARGS_LIBRARY_NAME)
                _error("Missing parameters in function call to "
                       "_download_library_url, please report this at "
                       "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        # Directories and files
        set(INTERNAL_LIBRARY_DIR "$ENV{INTERNAL_GET_PROJECT_DIR}/${ARGS_LIBRARY_NAME}")
        set(CACHE_DIR            "${INTERNAL_LIBRARY_DIR}/download_library")
        set(LIBRARY_DIR          "$ENV{GET_PROJECT_OUTPUT_DIR}/${ARGS_LIBRARY_NAME}")
        set(HASH_VAR_NAME        "GetProject_${ARGS_LIBRARY_NAME}_HASH")

        # Create library internal directory
        if (NOT EXISTS ${INTERNAL_LIBRARY_DIR})
                file(MAKE_DIRECTORY ${INTERNAL_LIBRARY_DIR})
                file(MAKE_DIRECTORY ${CACHE_DIR})
        endif ()

        # Download library archive
        _download_file(
                URL         ${ARGS_URL}
                DIRECTORY   ${CACHE_DIR}
                HASH        ${${HASH_VAR_NAME}}
                HASH_TYPE   "MD5"
                OUTPUT_HASH NEW_HASH)

        # Don't waste time extracting stuff again if hashes match
        if (DEFINED ${HASH_VAR_NAME} AND "${NEW_HASH}" STREQUAL "${${HASH_VAR_NAME}}")
                _is_directory_empty(
                        LIBRARY_DIR     ${LIBRARY_DIR}
                        OUTPUT_VARIABLE LIBRARY_DIR_EMPTY)

                if (NOT LIBRARY_DIR_EMPTY)
                        message(STATUS "GetProject: Old and new downloaded file hashes match, "
                                       "but '${ARGS_LIBRARY_NAME}' directory does "
                                       "not exist / is empty, extracting...")
                else ()
                        message(STATUS "GetProject: Old and new downloaded file hashes match. "
                                       "Not Extracting.")

                        return()
                endif ()
        else ()
                message(STATUS "GetProject: Old and new downloaded file hashes don't match, "
                               "extracting...")
        endif ()

        set(${HASH_VAR_NAME} ${NEW_HASH} CACHE STRING "${ARGS_LIBRARY_NAME} hash" FORCE)

        # Delete old extracted data
        if (EXISTS ${LIBRARY_DIR})
                file(REMOVE_RECURSE ${LIBRARY_DIR})
        endif ()

        _extract_archive(
                LIBRARY_NAME ${ARGS_LIBRARY_NAME})
endfunction ()

function (_validate_git_repo)
        set(ONE_VALUE_ARGS
                GIT_REPOSITORY
                OUTPUT_VALID)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_GIT_REPOSITORY)
                _error("Missing parameters in function call to "
                       "_validate_git_repo, please report this at "
                       "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        # If connected to the internet validate the git repository
        # without cloning.
        execute_process(
                COMMAND         git ls-remote ${ARGS_GIT_REPOSITORY}
                RESULT_VARIABLE GIT_CHECK_RESULT
                OUTPUT_QUIET
                ERROR_QUIET)

        if(NOT GIT_CHECK_RESULT EQUAL 0)
                set(${ARGS_OUTPUT_VALID} OFF PARENT_SCOPE)
        else ()
                set(${ARGS_OUTPUT_VALID} ON PARENT_SCOPE)
        endif()
endfunction ()

function (_download_library_git)
        set(ONE_VALUE_ARGS
                GIT_REPOSITORY
                LIBRARY_DIR
                VERSION
                BRANCH
                KEEP_UPDATED)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "" ${ARGN})

        if (NOT ARGS_GIT_REPOSITORY OR (NOT ARGS_BRANCH AND NOT ARGS_VERSION) OR NOT ARGS_LIBRARY_DIR)
                message(FATAL_ERROR "Missing parameters in function call to "
                                    "_download_library_git, please report this at "
                                    "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        # Save the version or the branch in the COMMAND_BRANCH variable,
        # as you can use the --branch option to pass tags.
        if (NOT ARGS_BRANCH)
                set(COMMAND_BRANCH ${ARGS_VERSION})
        else ()
                set(COMMAND_BRANCH ${ARGS_BRANCH})
        endif ()

        # Commands
        set(GIT_CLONE_COMMAND ${GIT_EXECUTABLE} clone ${ARGS_GIT_REPOSITORY}
                --branch ${COMMAND_BRANCH}
                --recurse-submodules
                -j 8
                --depth 1
                -c advice.detachedHead=false
                --quiet
                ${ARGS_LIBRARY_DIR})

        execute_process(
                COMMAND ${GIT_CLONE_COMMAND}
                OUTPUT_QUIET
                ERROR_QUIET)
endfunction ()

function (_add_subdirectory)
        set(ONE_VALUE_ARGS
                LIBRARY_NAME
                INSTALL_ENABLED)
        set(MULTI_VALUE_ARGS
                OPTIONS)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "${MULTI_VALUE_ARGS}" ${ARGN})

        if (NOT ARGS_LIBRARY_NAME)
                message(FATAL_ERROR "Missing parameters in function call to "
                        "_add_subdirectory, please report this at "
                        "${GET_PROJECT_REPO_URL}/issues.")
        endif ()

        # Directories
        set(LIBRARY_DIR         "$ENV{GET_PROJECT_OUTPUT_DIR}/${ARGS_LIBRARY_NAME}")
        set(INTERNAL_BINARY_DIR "$ENV{INTERNAL_BUILD_GET_PROJECT_DIR}/${ARGS_LIBRARY_NAME}")

        # If the library does not have CMake support. The inclusion must
        # be handled by the user.
        if (NOT EXISTS "${LIBRARY_DIR}/CMakeLists.txt")
                message(WARNING "CMakeLists.txt file not found in library "
                                "'${ARGS_LIBRARY_NAME}'. Not adding as a "
                                "subdirectory.")
                return()
        endif ()

        # Define variables for external use.
        set(${ARGS_LIBRARY_NAME}_ADDED ON PARENT_SCOPE)

        # Define options
        set (REGEXP "^(.+)=(.+)$")
        foreach (OPTION IN LISTS ARGS_OPTIONS)
                if (NOT ${OPTION} MATCHES ${REGEXP})
                        message(FATAL_ERROR "Option '${OPTION}' not recognized. "
                                            "Use the format NAME=VALUE")
                endif ()

                string(REGEX MATCH ${REGEXP} OUT ${OPTION})
                set(${CMAKE_MATCH_1} ${CMAKE_MATCH_2})
        endforeach ()

        add_subdirectory(${LIBRARY_DIR} ${INTERNAL_BINARY_DIR} EXCLUDE_FROM_ALL)

        # To install a directory it's required that the library is built.
        # TODO find something better
        if (ARGS_INSTALL_ENABLED)
                message(STATUS "GetProject: Installing ${ARGS_LIBRARY_NAME}...")
                set(BUILD_DIR "${INTERNAL_BINARY_DIR}/build/")

                foreach (OPTION IN LISTS ARGS_OPTIONS)
                        list(APPEND DEFINITIONS "-D${OPTION}")
                endforeach ()

                set(CONFIG_ARGS
                        -G "${CMAKE_GENERATOR}"
                        -S ${LIBRARY_DIR}
                        -B ${BUILD_DIR}
                        -DCMAKE_INSTALL_PREFIX:PATH=${LIBRARY_DIR}
                        ${DEFINITIONS})

                set(BUILD_COMMAND --build ${BUILD_DIR})
                if (NOT "${CMAKE_BUILD_TYPE}" STREQUAL "")
                        set(BUILD_COMMAND ${BUILD_COMMAND} --config "${CMAKE_BUILD_TYPE}")
                endif ()

                set(INSTALL_COMMAND --build ${BUILD_DIR} --target install)
                if (NOT "${CMAKE_BUILD_TYPE}" STREQUAL "")
                        set(INSTALL_COMMAND ${INSTALL_COMMAND} --config "${CMAKE_BUILD_TYPE}")
                endif ()

                execute_process(COMMAND ${CMAKE_COMMAND} . ${CONFIG_ARGS}
                        OUTPUT_QUIET
                        WORKING_DIRECTORY ${LIBRARY_DIR})

                execute_process(COMMAND ${CMAKE_COMMAND} ${BUILD_COMMAND}
                        OUTPUT_QUIET
                        WORKING_DIRECTORY ${LIBRARY_DIR})

                execute_process(COMMAND ${CMAKE_COMMAND} ${INSTALL_COMMAND}
                        OUTPUT_QUIET
                        WORKING_DIRECTORY ${LIBRARY_DIR})

                message(STATUS "GetProject: ${ARGS_LIBRARY_NAME} installed.")
        endif ()
endfunction ()

# ----------------------------------------------------------------------------------------------------------------------
# END-USER FUNCTIONS
# ----------------------------------------------------------------------------------------------------------------------

function (get_project)
        set(ONE_VALUE_ARGS
                URL
                GIT_REPOSITORY
                FILE
                LIBRARY_NAME
                INSTALL_ENABLED
                DOWNLOAD_ONLY
                BRANCH
                KEEP_UPDATED
                VERSION)
        set(MULTI_VALUE_ARGS
                OPTIONS)
        cmake_parse_arguments(ARGS "" "${ONE_VALUE_ARGS}" "${MULTI_VALUE_ARGS}" ${ARGN})

        if (ARGS_GIT_REPOSITORY)
                find_package(Git)
                if (NOT GIT_FOUND)
                        message(FATAL_ERROR "Git is required to use GetProject "
                                "with the GIT_REPOSITORY parameter. You can "
                                "download git at https://git-scm.com/downloads")
                endif ()
        endif ()

        _validate_args(${ARGV})

        if (ARGS_FILE)
                set(ARGS_DOWNLOAD_ONLY ON)
        endif ()

        # If the library is downloaded via git, validate the repo and get the name.
        if (ARGS_GIT_REPOSITORY)
                # If connected to the internet validate the git repository
                # without cloning
                _validate_git_repo(
                        GIT_REPOSITORY ${ARGS_GIT_REPOSITORY}
                        OUTPUT_VALID   REPO_VALID)

                if (NOT REPO_VALID)
                        message(WARNING "Invalid or inaccessible git repository "
                                        "'${ARGS_GIT_REPOSITORY}'. Not downloading.")
                        return()
                endif ()

                # Extract the library name from the GIT_REPOSITORY parameter and
                # save it in ARGS_LIBRARY_NAME if the user didn't provide one.
                if (NOT ARGS_LIBRARY_NAME)
                        string(REGEX MATCH ".*/([^/.]+)/([^/.]+)(\\.git)?$" _ ${ARGS_GIT_REPOSITORY})
                        set(LIBRARY_AUTHOR    "${CMAKE_MATCH_1}")
                        set(ARGS_LIBRARY_NAME "${CMAKE_MATCH_2}")
                endif ()
        endif ()

        # Directories and files
        set(LIBRARY_DIR          "$ENV{GET_PROJECT_OUTPUT_DIR}/${ARGS_LIBRARY_NAME}")
        set(INTERNAL_LIBRARY_DIR "$ENV{INTERNAL_GET_PROJECT_DIR}/${ARGS_LIBRARY_NAME}")
        set(INTERNAL_BINARY_DIR  "$ENV{INTERNAL_BUILD_GET_PROJECT_DIR}/${ARGS_LIBRARY_NAME}")
        message(STATUS "GetProject: Adding '${ARGS_LIBRARY_NAME}'.")

        if (NOT EXISTS "${INTERNAL_LIBRARY_DIR}")
                file(MAKE_DIRECTORY "${INTERNAL_LIBRARY_DIR}")
        endif ()
        if (NOT EXISTS "${INTERNAL_BINARY_DIR}")
                file(MAKE_DIRECTORY "${INTERNAL_BINARY_DIR}")
        endif ()

        if (ARGS_GIT_REPOSITORY)
                # Check if the given version is set as null or latest, if
                # so fetch the latest release.
                string(TOUPPER "${ARGS_VERSION}" CAPS_VERSION)
                if (ARGS_BRANCH OR NOT ARGS_VERSION OR "${CAPS_VERSION}" STREQUAL "LATEST")
                        _get_latest_tag(
                                GIT_REPOSITORY  ${ARGS_GIT_REPOSITORY}
                                LIBRARY_AUTHOR  ${LIBRARY_AUTHOR}
                                LIBRARY_NAME    ${ARGS_LIBRARY_NAME}
                                CLEAR           OFF
                                BRANCH          ${ARGS_BRANCH}
                                OUTPUT_VARIABLE ARGS_VERSION)
                endif ()
        endif ()

        # Use a .lock file to check if a parallel configuration is already
        # downloading the library. Until LOCK_FILE is delete, use _error
        # instead of message(FATAL_ERROR ...).
        set(LOCK_FILE "$ENV{GET_PROJECT_OUTPUT_DIR}/${ARGS_LIBRARY_NAME}.lock")
        if (EXISTS ${LOCK_FILE})
                message(FATAL_ERROR "Library '${ARGS_LIBRARY_NAME}' is already "
                                    "being downloaded, parallel configures are "
                                    "not supported.")
        endif ()

        file(WRITE "${LOCK_FILE}" "${ARGS_LIBRARY_NAME}")

        if (ARGS_GIT_REPOSITORY)
                _clear_if_necessary(
                        LIBRARY_NAME                ${ARGS_LIBRARY_NAME}
                        LIBRARY_DIR                 ${LIBRARY_DIR}
                        VERSION                     ${ARGS_VERSION}
                        BRANCH                      ${ARGS_BRANCH}
                        OUTPUT_SHOULD_SKIP_DOWNLOAD SHOULD_SKIP_DOWNLOAD)
        endif ()

        if (ARGS_FILE)
                set(HASH_VAR_NAME "GetProject_${ARGS_LIBRARY_NAME}_HASH")
                _download_file(
                        URL         ${ARGS_URL}
                        DIRECTORY   ${LIBRARY_DIR}
                        HASH        ${${HASH_VAR_NAME}}
                        HASH_TYPE   "MD5"
                        OUTPUT_HASH NEW_HASH)

                set(${HASH_VAR_NAME} ${NEW_HASH} CACHE STRING "${ARGS_LIBRARY_NAME} hash" FORCE)
        elseif (ARGS_URL)
                _download_library_url(
                        URL          ${ARGS_URL}
                        LIBRARY_NAME ${ARGS_LIBRARY_NAME})
        elseif (ARGS_GIT_REPOSITORY AND NOT SHOULD_SKIP_DOWNLOAD)
                _download_library_git(
                        GIT_REPOSITORY ${ARGS_GIT_REPOSITORY}
                        LIBRARY_DIR    ${LIBRARY_DIR}
                        VERSION        ${ARGS_VERSION}
                        BRANCH         ${ARGS_BRANCH}
                        KEEP_UPDATED   ${ARGS_KEEP_UPDATED})
        endif ()

        set(${ARGS_LIBRARY_NAME}_DOWNLOADED ON PARENT_SCOPE)
        set(${ARGS_LIBRARY_NAME}_VERSION    ${ARGS_VERSION} PARENT_SCOPE)
        set(${ARGS_LIBRARY_NAME}_SOURCE     ${LIBRARY_DIR} PARENT_SCOPE)
        set(${ARGS_LIBRARY_NAME}_BINARY     ${INTERNAL_BINARY_DIR} PARENT_SCOPE)

        file(REMOVE "${LOCK_FILE}")
        if (ARGS_DOWNLOAD_ONLY)
                return()
        endif ()

        _add_subdirectory(
                LIBRARY_NAME    ${ARGS_LIBRARY_NAME}
                INSTALL_ENABLED ${ARGS_INSTALL_ENABLED}
                OPTIONS         ${ARGS_OPTIONS})

        set(${ARGS_LIBRARY_NAME}_ADDED ON PARENT_SCOPE)
endfunction ()
