project(indium-test-addressing)

add_executable(indium-test-addressing addressing.cpp)

add_custom_command(
	OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/addressing.h"
	COMMAND xxd -i -n "addressing_metallib" "${CMAKE_CURRENT_SOURCE_DIR}/addressing.metallib" "${CMAKE_CURRENT_BINARY_DIR}/addressing.h"
	DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/addressing.metallib"
)
target_sources(indium-test-addressing PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/addressing.h")

target_include_directories(indium-test-addressing PRIVATE
	"${CMAKE_CURRENT_BINARY_DIR}"
)

target_link_libraries(indium-test-addressing PRIVATE
	indium_kit
	indium_private
)

set_target_properties(indium-test-addressing
	PROPERTIES
		CXX_STANDARD 17
		CXX_STANDARD_REQUIRED ON
		CXX_EXTENSIONS OFF
)
