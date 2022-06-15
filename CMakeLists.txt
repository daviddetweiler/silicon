cmake_minimum_required(VERSION 3.22)
project(silicon)
add_executable(silicon main.c)
set_property(TARGET silicon PROPERTY C_STANDARD 17)
