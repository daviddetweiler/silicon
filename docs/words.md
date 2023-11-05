# Input Parsing

    accept_word
    parse_number
    parse_unumber
    parsed_number
    negative
    repl_accept_line
    repl_accept_line_interactive
    repl_accept_line_interactive_nolog
    repl_accept_line_source_text
    repl_buffer
    repl_read_line
    reset_current_word
    set_line_size
    consume_space
    consume_word
    check_is_digit
    check_is_space
    flush_line
    get_current_word

# System Functions

    allocate_pages
    free_pages
    exit_process
    await
    set_file_ptr
    get_handle
    create_file
    close_handle
    write_file
    open_file
    read_file
    check_is_console_handle

# Word Assembly Helpers

    assemble
    assemble_blob
    assemble_branch
    assemble_byte
    assemble_invoke_constant
    assemble_invoke_string
    assemble_invoke_thread
    assemble_invoke_variable
    assemble_jump
    assemble_literal
    assembly_arena
    assembly_arena_allocate
    assembly_arena_check_bounds
    assembly_arena_start_block
    assembly_arena_top
    assembly_ptr
    cell_align_assembly_arena

# Initialization Sequence

    init_assembler
    init_assembly_arena
    init_dictionary
    init_handles
    init_imports
    init_logging
    init_source_context_stack
    init_terminal
    load_core_library

# Stack Manipulation

    nip
    over
    over_pair
    pair_over
    rot_down
    swap
    copy
    copy_pair
    drop
    drop_pair
    literal

# Memory Access

    load
    load_2nd
    load_byte
    load_pair

    store
    store_2nd
    store_byte
    store_pair

# Terminal I/O

    input_buffer
    print
    print_line
    stdin_handle
    stdout_handle
    term_read_line
    term_check_is_buffer_full
    is_terminal_piped
    pipe_read_line
    read_line
    new_line
    newline
    newline_code

# Dictionary

    dictionary
    entry_data_ptr
    entry_immediate
    entry_name
    make_immediate
    find
    find_next_word
    create

# VT Sequences

    seq_bright_magenta
    seq_clear
    seq_clear_all
    seq_cyan
    seq_default
    seq_red
    seq_yellow

# Source Stack

    source_clear
    source_context
    source_context_stack
    source_current_word
    source_full_text
    source_is_nested
    source_line_size
    source_line_start
    source_pop
    source_push
    source_push_buffer

# Stack Primitives

    stack_add
    stack_and
    stack_div
    stack_eq
    stack_eq0
    stack_gt
    stack_gte
    stack_inc
    stack_lt
    stack_lt0
    stack_lte
    stack_mod
    stack_mul
    stack_neg
    stack_neq
    stack_neq0
    stack_not
    stack_or
    stack_peek
    stack_pop
    stack_push
    stack_shl
    stack_shr
    stack_sub
    stack_udiv
    stack_umod
    stack_umul

# Status Strings

    status_abort
    status_assembly_bounds
    status_bad_init
    status_fatal
    status_file_handle_load_failure
    status_log_failure
    status_nested_def
    status_no_word
    status_overfull
    status_script_not_found
    status_stacks_unset
    status_underflow
    status_unknown
    status_word_too_long

# Control Flow

    invoke
    maybe_execute
    jump
    predicate
    return
    branch

# Uncategorized

    string_eq
    copy_blob
    cell_align
    clear_data_stack
    get_data_stack
    clear_return_stack
    get_return_stack

# Interpreter

    version_banner
    interpreter
    is_assembling
    is_initializing
    log_file_handle
    log_name
    should_exit
    core_vocabulary
    current_definition
    exit

# File Interpretation

    execute
    file_handle_load_content
    load_file
    load_length
    file_size

# Fault Handling

    test_stacks
    report_leftovers
    report_underflow
    soft_fault
    hard_fault
    check_no_underflow
    break
    crash

# Constants

    ten
    cell_size
    two
    one
    zero
    all_ones
    ptr_invoke_thread
    text_size
    rdata_size
    bss_size
    return_stack_base
    data_stack_base
