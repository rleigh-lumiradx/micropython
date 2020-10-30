# CMake fragment for MicroPython rules

find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(MICROPY_PY_QSTRDEFS "${MICROPY_PY_DIR}/qstrdefs.h")
set(MICROPY_GENHDR_DIR "${CMAKE_BINARY_DIR}/genhdr")
set(MICROPY_QSTRDEFS_CONCAT "${MICROPY_GENHDR_DIR}/qstrdefs_concat.h")
set(MICROPY_MPVERSION "${MICROPY_GENHDR_DIR}/mpversion.h")
set(MICROPY_MODULEDEFS "${MICROPY_GENHDR_DIR}/moduledefs.h")
set(MICROPY_QSTR_DEFS_LAST "${MICROPY_GENHDR_DIR}/qstr.i.last")
set(MICROPY_QSTR_DEFS_SPLIT "${MICROPY_GENHDR_DIR}/qstr.split")
set(MICROPY_QSTR_DEFS_COLLECTED "${MICROPY_GENHDR_DIR}/qstrdefs.collected.h")
set(MICROPY_QSTR_DEFS_PREPROCESSED_QUOTED "${MICROPY_GENHDR_DIR}/qstrdefs.preprocessed_quoted.h")
set(MICROPY_QSTR_DEFS_PREPROCESSED "${MICROPY_GENHDR_DIR}/qstrdefs.preprocessed.h")
set(MICROPY_QSTR_DEFS_GENERATED "${MICROPY_GENHDR_DIR}/qstrdefs.generated.h")

target_sources(${MICROPY_TARGET} PRIVATE
    ${MICROPY_MPVERSION}
    ${MICROPY_QSTR_DEFS_GENERATED}
)

# Command to force the build of another command

add_custom_command(
    OUTPUT MICROPY_FORCE_BUILD
    COMMENT ""
    COMMAND echo -n
)

# Generate mpversion.h

add_custom_command(
    OUTPUT ${MICROPY_MPVERSION}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${MICROPY_GENHDR_DIR}
    COMMAND ${Python3_EXECUTABLE} ${MICROPY_DIR}/py/makeversionhdr.py ${MICROPY_MPVERSION}
    DEPENDS MICROPY_FORCE_BUILD
)

# Generate moduledefs.h
# This is currently hard-coded to support modarray.c only, because makemoduledefs.py doesn't support absolute paths

add_custom_command(
    OUTPUT ${MICROPY_MODULEDEFS}
    COMMAND ${Python3_EXECUTABLE} ${MICROPY_PY_DIR}/makemoduledefs.py --vpath="." ../../../py/modarray.c > ${MICROPY_MODULEDEFS}
    DEPENDS ${MICROPY_MPVERSION}
        ${MICROPY_SOURCE_QSTR}
)

# Generate qstrs

get_property_and_add_prefix(micropython_includes_raw ${MICROPY_TARGET} INCLUDE_DIRECTORIES "-I")
process_flags(C micropython_includes_raw micropython_includes)
get_property_and_add_prefix(micropython_definitions_raw ${MICROPY_TARGET} COMPILE_DEFINITIONS "-D")
process_flags(C micropython_definitions_raw micropython_definitions)

set(includes -I$<JOIN:$<TARGET_PROPERTY:zephyr_interface,INTERFACE_INCLUDE_DIRECTORIES>,$<SEMICOLON>-I>)
set(system_includes -I$<JOIN:$<TARGET_PROPERTY:zephyr_interface,INTERFACE_SYSTEM_INCLUDE_DIRECTORIES>,$<SEMICOLON>-I>)
set(definitions -D$<JOIN:$<TARGET_PROPERTY:zephyr_interface,INTERFACE_COMPILE_DEFINITIONS>,$<SEMICOLON>-D>)

zephyr_get_compile_options_for_lang(C options)
# For add_custom_command to properly handle argument escaping in lists or generator expressions,
# the items have to separated by semicolons and not spaces. Zephyr uses spaces, so we need to then.
# see also https://gitlab.kitware.com/cmake/cmake/-/merge_requests/377
string(REGEX REPLACE "^ *(.*), (-?[a-zA-Z]*)>$" "\\1,$<SEMICOLON>\\2>" options ${options})

set(THE_FLAGS ${micropython_includes} ${micropython_definitions} ${includes} ${system_includes} ${definitions} ${options})


# If any of the dependencies in this rule change then the C-preprocessor step must be run.
# It only needs to be passed the list of MICROPY_SOURCE_QSTR files that have changed since it was
# last run, but it looks like it's not possible to specify that with cmake.
add_custom_command(
    OUTPUT ${MICROPY_QSTR_DEFS_LAST}
    COMMAND ${CMAKE_C_COMPILER} -E ${THE_FLAGS} -DNO_QSTR ${MICROPY_SOURCE_QSTR} > ${MICROPY_GENHDR_DIR}/qstr.i.last
    DEPENDS ${MICROPY_MODULEDEFS}
        ${MICROPY_SOURCE_QSTR}
    VERBATIM
    COMMAND_EXPAND_LISTS
)

add_custom_command(
    OUTPUT ${MICROPY_QSTR_DEFS_SPLIT}
    COMMAND ${Python3_EXECUTABLE} ${MICROPY_DIR}/py/makeqstrdefs.py split qstr ${MICROPY_GENHDR_DIR}/qstr.i.last ${MICROPY_GENHDR_DIR}/qstr _
    COMMAND "${CMAKE_COMMAND}" -E touch ${MICROPY_QSTR_DEFS_SPLIT}
    DEPENDS ${MICROPY_QSTR_DEFS_LAST}
    VERBATIM
)

add_custom_command(
    OUTPUT ${MICROPY_QSTR_DEFS_COLLECTED}
    COMMAND ${Python3_EXECUTABLE} ${MICROPY_DIR}/py/makeqstrdefs.py cat qstr _ ${MICROPY_GENHDR_DIR}/qstr ${MICROPY_QSTR_DEFS_COLLECTED}
    DEPENDS ${MICROPY_QSTR_DEFS_SPLIT}
    VERBATIM
)

file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/gen_qstrdefs_concat_quote.cmake"
    CONTENT "# Generate ${MICROPY_QSTRDEFS_CONCAT} with Q() quotes
file(REMOVE \"${MICROPY_QSTRDEFS_CONCAT}\")
foreach(file \"${MICROPY_PY_QSTRDEFS}\" \"${MICROPY_QSTR_DEFS_COLLECTED}\")
    file(STRINGS \"\${file}\" CONTENTS)
    foreach(line \${CONTENTS})
        # Apply regex to quote Q()s
        string(REGEX REPLACE \"^(Q\\\\(.*\\\\))\" \"\\\"\\\\1\\\"\" replaced \"\${line}\")
        file(APPEND \"${MICROPY_QSTRDEFS_CONCAT}\" \"\${replaced}\\n\")
    endforeach()
endforeach()
")

file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/gen_qstrdefs_dequote.cmake"
    CONTENT "# Generate ${MICROPY_QSTR_DEFS_PREPROCESSED} from ${MICROPY_QSTR_DEFS_PREPROCESSED_QUOTED} with quotes removed
file(REMOVE \"${MICROPY_QSTR_DEFS_PREPROCESSED}\")
file(STRINGS \"${MICROPY_QSTR_DEFS_PREPROCESSED_QUOTED}\" CONTENTS)
foreach(line \${CONTENTS})
    # Apply regex to dequote Q()s
    string(REGEX REPLACE \"^\\\"(Q\\\\(.*\\\\))\\\"\" \"\\\\1\" replaced \"\${line}\")
    file(APPEND \"${MICROPY_QSTR_DEFS_PREPROCESSED}\" \"\${replaced}\\n\")
endforeach()
")

add_custom_command(OUTPUT "${MICROPY_QSTRDEFS_CONCAT}"
    COMMAND "${CMAKE_COMMAND}" -P "${CMAKE_CURRENT_BINARY_DIR}/gen_qstrdefs_concat_quote.cmake"
    DEPENDS "${MICROPY_PY_QSTRDEFS}" "${MICROPY_QSTR_DEFS_COLLECTED}" "${CMAKE_CURRENT_BINARY_DIR}/gen_qstrdefs_concat_quote.cmake"
    VERBATIM
)

add_custom_command(
    OUTPUT ${MICROPY_QSTR_DEFS_PREPROCESSED_QUOTED}
    COMMAND ${CMAKE_C_COMPILER} -E ${THE_FLAGS} ${MICROPY_QSTRDEFS_CONCAT} > ${MICROPY_QSTR_DEFS_PREPROCESSED_QUOTED}
    DEPENDS "${MICROPY_QSTRDEFS_CONCAT}"
    VERBATIM
    COMMAND_EXPAND_LISTS
)

add_custom_command(OUTPUT "${MICROPY_QSTR_DEFS_PREPROCESSED}"
        COMMAND "${CMAKE_COMMAND}" -P "${CMAKE_CURRENT_BINARY_DIR}/gen_qstrdefs_dequote.cmake"
        DEPENDS "${MICROPY_QSTR_DEFS_PREPROCESSED_QUOTED}" "${CMAKE_CURRENT_BINARY_DIR}/gen_qstrdefs_dequote.cmake"
        VERBATIM
        )

add_custom_command(
    OUTPUT ${MICROPY_QSTR_DEFS_GENERATED}
    COMMAND ${Python3_EXECUTABLE} ${MICROPY_PY_DIR}/makeqstrdata.py ${MICROPY_QSTR_DEFS_PREPROCESSED} > ${MICROPY_QSTR_DEFS_GENERATED}
    DEPENDS ${MICROPY_QSTR_DEFS_PREPROCESSED}
    VERBATIM
)

# Build frozen code if enabled

if(MICROPY_FROZEN_MANIFEST)
    set(MICROPY_FROZEN_CONTENT "${CMAKE_BINARY_DIR}/frozen_content.c")

    target_sources(${MICROPY_TARGET} PRIVATE
        ${MICROPY_FROZEN_CONTENT}
    )

    target_compile_definitions(${MICROPY_TARGET} PUBLIC
        MICROPY_QSTR_EXTRA_POOL=mp_qstr_frozen_const_pool
        MICROPY_MODULE_FROZEN_MPY=\(1\)
    )

    add_custom_command(
        OUTPUT ${MICROPY_FROZEN_CONTENT}
        COMMAND ${Python3_EXECUTABLE} ${MICROPY_DIR}/tools/makemanifest.py -o ${MICROPY_FROZEN_CONTENT} -v "MPY_DIR=${MICROPY_DIR}" -v "PORT_DIR=${MICROPY_PORT_DIR}" -b "${CMAKE_BINARY_DIR}" -f${MICROPY_CROSS_FLAGS} ${MICROPY_FROZEN_MANIFEST}
        DEPENDS MICROPY_FORCE_BUILD
            ${MICROPY_QSTR_DEFS_GENERATED}
        VERBATIM
    )
endif()
