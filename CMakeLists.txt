cmake_minimum_required(VERSION 3.8)
project(fastlio_postproc)

find_package(rosidl_default_generators REQUIRED)

# Find necessary packages
find_package(ament_cmake REQUIRED)

# Install directories
install(DIRECTORY
  config
  launch
  scripts
  templates
  DESTINATION share/${PROJECT_NAME}
)

install(PROGRAMS
  scripts/fastlio_postproc.sh
  DESTINATION lib/${PROJECT_NAME}
)

# Also create symlink in bin directory (for direct command line access)
install(PROGRAMS
  scripts/fastlio_postproc.sh
  DESTINATION bin
  RENAME fastlio_postproc
)

ament_package()
