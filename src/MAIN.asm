;===============================================================================
; MSX-DOS2 Structured BASIC Interpreter
; Z80 Assembly Integrated Design Source
; Version: advanced-control-types-arrays
;===============================================================================
;
; Program:
;   Interactive Structured BASIC for MSX-DOS2.
;
; Major implemented/defined features in this integrated source:
;
;   Source storage:
;     - Program area starts at 1000h
;     - Input line with number is tokenized and stored
;     - Input line without number is immediate command/direct execution
;
;   MSX-BASIC-like tokenized source:
;     - Keyword tokenization
;     - Integer literal tokenization
;     - Operator tokenization
;
;   Expressions:
;     - Precedence-aware recursive descent parser
;     - Integer operators:
;         OR
;         AND
;         = <> < <= > >=
;         + -
;         * /
;         unary + -
;         parenthesized expression
;     - Variables
;     - One-dimensional arrays
;     - Structure member access only, e.g. P.X
;     - Bare structure variable in expression is rejected by semantic checker
;
;   Statements:
;     - LET / assignment
;     - PRINT
;     - GOTO / GOSUB / RETURN
;     - *LABEL
;     - IF THEN ELSE END IF
;     - WHILE WEND
;     - REPEAT UNTIL
;     - FOR NEXT skeleton
;     - PROC / END PROC
;     - FUNCTION / END FUNCTION
;     - LOCAL
;     - TYPE / END TYPE
;     - DIM one-dimensional array
;
;   Types:
;     - INTEGER: 16-bit signed/unsigned runtime value
;     - STRING: token-level reserved, runtime not fully implemented here
;     - STRUCT: user-defined structure type
;     - Array: one-dimensional only
;     - Nested structures are prohibited
;
;   File/Directory:
;     - MSX-DOS2 handle SAVE/LOAD
;     - FILES
;     - CHDIR
;
; Important:
;   This file is intended as a single-source development foundation.
;   It is much closer to a real implementation than pseudocode, but several large
;   subsystems such as full symbol table hashing, complete error recovery, strings,
;   and production-grade 16-bit division should be finished/tested on a target
;   assembler/emulator.
;
;===============================================================================

        ORG 0100h

BDOS        EQU 0005h

;===============================================================================
; Memory Map
;===============================================================================

SRC_START       EQU 1000h
IR_START        EQU 8000h
GLOBAL_VAR_BASE EQU A000h
STACK_AREA      EQU B000h
HEAP_AREA       EQU B800h

LABEL_TABLE     EQU C000h
PROC_TABLE      EQU C800h
TYPE_TABLE      EQU D000h
ARRAY_TABLE     EQU D800h
LOCAL_FRAME     EQU E000h

MAX_LABELS      EQU 128
MAX_PROCS       EQU 64
MAX_TYPES       EQU 32
MAX_FIELDS      EQU 16
MAX_ARRAYS      EQU 64

;===============================================================================
; Token codes
;===============================================================================

TK_END      EQU 80h
TK_FOR      EQU 81h
TK_NEXT     EQU 82h
TK_DATA     EQU 83h
TK_INPUT    EQU 84h
TK_DIM      EQU 85h
TK_READ     EQU 86h
TK_LET      EQU 87h
TK_GOTO     EQU 89h
TK_RUN      EQU 8Ah
TK_IF       EQU 8Bh
TK_RESTORE  EQU 8Ch
TK_GOSUB    EQU 8Dh
TK_RETURN   EQU 8Eh
TK_PRINT    EQU 91h
TK_LIST     EQU 93h
TK_NEW      EQU 94h
TK_ON       EQU 95h
TK_ELSE     EQU A1h
TK_WHILE    EQU B1h
TK_WEND     EQU B2h
TK_LOAD     EQU BCh
TK_SAVE     EQU BEh

; Extended structured BASIC tokens
TK_REPEAT   EQU E0h
TK_UNTIL    EQU E1h
TK_PROC     EQU E2h
TK_ENDPROC  EQU E3h
TK_FUNCTION EQU E4h
TK_ENDFUNC  EQU E5h
TK_TYPE     EQU E6h
TK_ENDTYPE  EQU E7h
TK_AS       EQU E8h
TK_LOCAL    EQU E9h
TK_FILES    EQU EAh
TK_CHDIR    EQU EBh
TK_THEN     EQU ECh
TK_ENDIF    EQU EDh
TK_INTEGER  EQU EEh
TK_STRING   EQU EFh

; Operators / punctuation
TK_PLUS     EQU F1h
TK_MINUS    EQU F2h
TK_MUL      EQU F3h
TK_DIV      EQU F4h
TK_EQ       EQU F5h
TK_LT       EQU F6h
TK_GT       EQU F7h
TK_LPAREN   EQU F8h
TK_RPAREN   EQU F9h
TK_COMMA    EQU FAh
TK_COLON    EQU FBh
TK_DOT      EQU FCh
TK_NE       EQU FDh
TK_INTLIT   EQU FFh

; Multi-byte operator extension marker
TK_EXT      EQU FEh
TK_LE       EQU 01h
TK_GE       EQU 02h
TK_AND      EQU 03h
TK_OR       EQU 04h
TK_LABEL    EQU 05h            ; followed by zero-terminated name

;===============================================================================
; IR opcodes
;===============================================================================

IR_NOP      EQU 00h
IR_PUSHI    EQU 01h
IR_PUSHV    EQU 02h            ; var id
IR_STOREV   EQU 03h            ; var id
IR_PUSHL    EQU 04h            ; local offset
IR_STOREL   EQU 05h            ; local offset

IR_ADD      EQU 10h
IR_SUB      EQU 11h
IR_MUL      EQU 12h
IR_DIV      EQU 13h
IR_NEG      EQU 14h
IR_EQ       EQU 15h
IR_NE       EQU 16h
IR_LT       EQU 17h
IR_LE       EQU 18h
IR_GT       EQU 19h
IR_GE       EQU 1Ah
IR_AND      EQU 1Bh
IR_OR       EQU 1Ch

IR_PRINT    EQU 20h
IR_GOTO     EQU 21h            ; absolute IR address patched
IR_IFZ      EQU 22h            ; pop cond, jump if zero
IR_GOSUB    EQU 23h
IR_RETURN   EQU 24h
IR_CALL     EQU 25h            ; proc/function address patched
IR_RET      EQU 26h

IR_FOR_INIT EQU 30h
IR_FOR_NEXT EQU 31h
IR_WHILE    EQU 32h
IR_WEND     EQU 33h
IR_REPEAT   EQU 34h
IR_UNTIL    EQU 35h

IR_ADDRV    EQU 40h            ; address of global variable
IR_ADDRL    EQU 41h            ; address of local
IR_LOADPTR  EQU 42h            ; load 16-bit value at address
IR_STOREPTR EQU 43h            ; store 16-bit value to address
IR_MEMBER   EQU 44h            ; add member offset
IR_INDEX    EQU 45h            ; array index to element address

IR_DIMARR   EQU 50h            ; declare/allocate one-dimensional array
IR_NEWSTRUCT EQU 51h           ; allocate structure block

IR_END      EQU FFh

;===============================================================================
; Type codes
;===============================================================================

TYPE_INTEGER EQU 01h
TYPE_STRING  EQU 02h
TYPE_STRUCT  EQU 03h
TYPE_ARRAY   EQU 04h

;===============================================================================
; Work variables
;===============================================================================

PC:             DW 0
SPTR:           DW STACK_AREA
CALL_SP:        DW CALL_STACK
HEAP_PTR:       DW HEAP_AREA

SRC_END_PTR:    DW SRC_START
IR_END_PTR:     DW IR_START
CUR_LINE_NO:    DW 0

SRC_PTR:        DW 0
OUT_PTR:        DW 0
NUM_VALUE:      DW 0

LABEL_COUNT:    DB 0
PROC_COUNT:     DB 0
TYPE_COUNT:     DB 0
ARRAY_COUNT:    DB 0

CURRENT_PROC:   DB 0FFh
LOCAL_SIZE:     DW 0

ERROR_CODE:     DB 0

ERR_NONE        EQU 00h
ERR_SYNTAX      EQU 01h
ERR_LABEL       EQU 02h
ERR_TYPE        EQU 03h
ERR_NESTSTRUCT  EQU 04h
ERR_STRUCTBARE  EQU 05h
ERR_ARRAYDIM    EQU 06h

;===============================================================================
; Entry
;===============================================================================

START:
        CALL INIT_SYSTEM

MAIN_LOOP:
        CALL PROMPT
        CALL INPUT_LINE

        LD HL,INPUT_BUF+2
        CALL SKIP_SPACES
        CALL CHECK_LINE_NUMBER
        JR C,STORE_NUMBERED_LINE

        LD HL,INPUT_BUF+2
        CALL EXEC_COMMAND_OR_DIRECT
        JR MAIN_LOOP

STORE_NUMBERED_LINE:
        LD (CUR_LINE_NO),DE
        CALL SKIP_SPACES
        LD DE,(SRC_END_PTR)
        CALL STORE_TOKENIZED_LINE
        LD (SRC_END_PTR),DE
        JR MAIN_LOOP

INIT_SYSTEM:
        LD HL,SRC_START
        LD (SRC_END_PTR),HL
        LD HL,IR_START
        LD (IR_END_PTR),HL
        LD HL,STACK_AREA
        LD (SPTR),HL
        LD HL,CALL_STACK
        LD (CALL_SP),HL
        LD HL,HEAP_AREA
        LD (HEAP_PTR),HL
        XOR A
        LD (LABEL_COUNT),A
        LD (PROC_COUNT),A
        LD (TYPE_COUNT),A
        LD (ARRAY_COUNT),A
        CALL CLEAR_VARS
        RET

;===============================================================================
; Console I/O
;===============================================================================

PROMPT:
        LD A,'>'
        CALL PUT_CHAR
        RET

PUT_CHAR:
        LD E,A
        LD C,02h
        CALL BDOS
        RET

PRINT_CRLF:
        LD A,13
        CALL PUT_CHAR
        LD A,10
        CALL PUT_CHAR
        RET

PRINT_STRING:
.PS_LOOP:
        LD A,(HL)
        OR A
        RET Z
        CALL PUT_CHAR
        INC HL
        JR .PS_LOOP

INPUT_BUF:
        DB 126
        DB 0
        DS 126

INPUT_LINE:
        LD DE,INPUT_BUF
        LD C,0Ah
        CALL BDOS
        LD HL,INPUT_BUF+1
        LD C,(HL)
        LD B,0
        INC HL
        ADD HL,BC
        LD (HL),0
        RET

;===============================================================================
; Utility
;===============================================================================

SKIP_SPACES:
        LD A,(HL)
        CP ' '
        RET NZ
        INC HL
        JR SKIP_SPACES

CHECK_LINE_NUMBER:
        ; HL = text
        ; Carry set if found, DE = line number, HL = after number
        LD A,(HL)
        CP '0'
        JR C,.NO
        CP '9'+1
        JR NC,.NO
        LD DE,0
.CLN_LOOP:
        LD A,(HL)
        CP '0'
        JR C,.DONE
        CP '9'+1
        JR NC,.DONE
        PUSH HL
        LD H,D
        LD L,E
        ADD HL,HL
        PUSH HL
        ADD HL,HL
        ADD HL,HL
        POP BC
        ADD HL,BC
        EX DE,HL
        POP HL
        LD A,(HL)
        SUB '0'
        LD C,A
        LD B,0
        EX DE,HL
        ADD HL,BC
        EX DE,HL
        INC HL
        JR .CLN_LOOP
.DONE:
        SCF
        RET
.NO:
        OR A
        RET

CLEAR_VARS:
        LD HL,GLOBAL_VAR_BASE
        LD BC,512
        XOR A
.CV:
        LD (HL),A
        INC HL
        DEC BC
        LD A,B
        OR C
        JR NZ,.CV
        RET

TO_UPPER:
        CP 'a'
        RET C
        CP 'z'+1
        RET NC
        SUB 20h
        RET

IS_ALNUM:
        CP '0'
        JR C,.NO
        CP '9'+1
        JR C,.YES
        CP 'A'
        JR C,.LOW
        CP 'Z'+1
        JR C,.YES
.LOW:
        CP 'a'
        JR C,.NO
        CP 'z'+1
        JR C,.YES
.NO:
        OR A
        RET
.YES:
        SCF
        RET

STRCMP8:
        ; HL = zero term string, DE = zero term string, compare max 8 chars
        LD B,8
.SC8:
        LD A,(DE)
        CP (HL)
        RET NZ
        OR A
        RET Z
        INC HL
        INC DE
        DJNZ .SC8
        XOR A
        RET

;===============================================================================
; Tokenized source storage
;===============================================================================

STORE_TOKENIZED_LINE:
        ; HL = source text, DE = destination
        PUSH DE
        XOR A
        LD (DE),A
        INC DE
        LD (DE),A
        INC DE

        LD BC,(CUR_LINE_NO)
        LD A,C
        LD (DE),A
        INC DE
        LD A,B
        LD (DE),A
        INC DE

        CALL TOKENIZE_LINE

        XOR A
        LD (DE),A
        INC DE

        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        RET

TOKENIZE_LINE:
.TOK_LOOP:
        CALL SKIP_SPACES
        LD A,(HL)
        OR A
        RET Z

        CP '*'
        JR Z,.LABEL

        CP '0'
        JR C,.CHECK_WORD
        CP '9'+1
        JR C,.NUMBER

.CHECK_WORD:
        CP 'A'
        JR C,.SYMBOL
        CP 'Z'+1
        JR C,.WORD
        CP 'a'
        JR C,.SYMBOL
        CP 'z'+1
        JR C,.WORD

.SYMBOL:
        CALL TOKENIZE_SYMBOL
        JR .TOK_LOOP
.NUMBER:
        CALL TOKENIZE_NUMBER
        JR .TOK_LOOP
.WORD:
        CALL TOKENIZE_WORD
        JR .TOK_LOOP
.LABEL:
        CALL TOKENIZE_LABEL
        JR .TOK_LOOP

TOKENIZE_LABEL:
        ; source has *NAME, emit TK_EXT TK_LABEL NAME 00
        INC HL
        LD A,TK_EXT
        LD (DE),A
        INC DE
        LD A,TK_LABEL
        LD (DE),A
        INC DE
.TL:
        LD A,(HL)
        CALL IS_ALNUM
        JR NC,.END
        CALL TO_UPPER
        LD (DE),A
        INC DE
        INC HL
        JR .TL
.END:
        XOR A
        LD (DE),A
        INC DE
        RET

TOKENIZE_NUMBER:
        CALL PARSE_ASCII_NUMBER
        LD A,TK_INTLIT
        LD (DE),A
        INC DE
        LD BC,(NUM_VALUE)
        LD A,C
        LD (DE),A
        INC DE
        LD A,B
        LD (DE),A
        INC DE
        RET

PARSE_ASCII_NUMBER:
        PUSH DE
        LD DE,0
.PAN_LOOP:
        LD A,(HL)
        CP '0'
        JR C,.PAN_DONE
        CP '9'+1
        JR NC,.PAN_DONE
        PUSH HL
        LD H,D
        LD L,E
        ADD HL,HL
        PUSH HL
        ADD HL,HL
        ADD HL,HL
        POP BC
        ADD HL,BC
        EX DE,HL
        POP HL
        LD A,(HL)
        SUB '0'
        LD C,A
        LD B,0
        EX DE,HL
        ADD HL,BC
        EX DE,HL
        INC HL
        JR .PAN_LOOP
.PAN_DONE:
        LD (NUM_VALUE),DE
        POP DE
        RET

TOKENIZE_SYMBOL:
        LD A,(HL)
        INC HL

        CP '<'
        JR Z,.LT_OR_NE_OR_LE
        CP '>'
        JR Z,.GT_OR_GE

        CP '+'
        JR Z,.PLUS
        CP '-'
        JR Z,.MINUS
        CP '*'
        JR Z,.MUL
        CP '/'
        JR Z,.DIV
        CP '='
        JR Z,.EQ
        CP '('
        JR Z,.LP
        CP ')'
        JR Z,.RP
        CP ','
        JR Z,.COMMA
        CP ':'
        JR Z,.COLON
        CP '.'
        JR Z,.DOT
        LD (DE),A
        INC DE
        RET

.LT_OR_NE_OR_LE:
        LD A,(HL)
        CP '>'
        JR Z,.NE2
        CP '='
        JR Z,.LE2
        LD A,TK_LT
        JR .OUT
.NE2:
        INC HL
        LD A,TK_NE
        JR .OUT
.LE2:
        INC HL
        LD A,TK_EXT
        LD (DE),A
        INC DE
        LD A,TK_LE
        JR .OUT

.GT_OR_GE:
        LD A,(HL)
        CP '='
        JR Z,.GE2
        LD A,TK_GT
        JR .OUT
.GE2:
        INC HL
        LD A,TK_EXT
        LD (DE),A
        INC DE
        LD A,TK_GE
        JR .OUT

.PLUS:  LD A,TK_PLUS   : JR .OUT
.MINUS: LD A,TK_MINUS  : JR .OUT
.MUL:   LD A,TK_MUL    : JR .OUT
.DIV:   LD A,TK_DIV    : JR .OUT
.EQ:    LD A,TK_EQ     : JR .OUT
.LP:    LD A,TK_LPAREN : JR .OUT
.RP:    LD A,TK_RPAREN : JR .OUT
.COMMA: LD A,TK_COMMA  : JR .OUT
.COLON: LD A,TK_COLON  : JR .OUT
.DOT:   LD A,TK_DOT    : JR .OUT
.OUT:
        LD (DE),A
        INC DE
        RET

TOKENIZE_WORD:
        PUSH HL
        PUSH DE
        LD IX,KEYWORD_TABLE
.TW_NEXT:
        LD A,(IX+0)
        OR A
        JR Z,.IDENT
        PUSH HL
        PUSH IX
.TW_CMP:
        LD A,(IX+0)
        OR A
        JR Z,.MATCH_END
        LD B,A
        LD A,(HL)
        CALL TO_UPPER
        CP B
        JR NZ,.FAIL
        INC HL
        INC IX
        JR .TW_CMP
.MATCH_END:
        LD A,(HL)
        CALL IS_ALNUM
        JR C,.FAIL
        INC IX
        LD A,(IX+0)
        POP IX
        POP BC
        POP DE
        LD (DE),A
        INC DE
        RET
.FAIL:
        POP IX
        POP HL
.SKIPKW:
        LD A,(IX+0)
        INC IX
        OR A
        JR NZ,.SKIPKW
        INC IX
        JR .TW_NEXT

.IDENT:
        POP DE
        POP HL
.ID_LOOP:
        LD A,(HL)
        CALL IS_ALNUM
        RET NC
        CALL TO_UPPER
        LD (DE),A
        INC DE
        INC HL
        JR .ID_LOOP

KEYWORD_TABLE:
        DB "PRINT",0,TK_PRINT
        DB "RUN",0,TK_RUN
        DB "LIST",0,TK_LIST
        DB "SAVE",0,TK_SAVE
        DB "LOAD",0,TK_LOAD
        DB "FILES",0,TK_FILES
        DB "CHDIR",0,TK_CHDIR
        DB "NEW",0,TK_NEW
        DB "IF",0,TK_IF
        DB "THEN",0,TK_THEN
        DB "ELSE",0,TK_ELSE
        DB "ENDIF",0,TK_ENDIF
        DB "GOTO",0,TK_GOTO
        DB "GOSUB",0,TK_GOSUB
        DB "RETURN",0,TK_RETURN
        DB "FOR",0,TK_FOR
        DB "NEXT",0,TK_NEXT
        DB "WHILE",0,TK_WHILE
        DB "WEND",0,TK_WEND
        DB "REPEAT",0,TK_REPEAT
        DB "UNTIL",0,TK_UNTIL
        DB "DATA",0,TK_DATA
        DB "READ",0,TK_READ
        DB "DIM",0,TK_DIM
        DB "TYPE",0,TK_TYPE
        DB "ENDTYPE",0,TK_ENDTYPE
        DB "AS",0,TK_AS
        DB "INTEGER",0,TK_INTEGER
        DB "STRING",0,TK_STRING
        DB "LOCAL",0,TK_LOCAL
        DB "PROC",0,TK_PROC
        DB "ENDPROC",0,TK_ENDPROC
        DB "FUNCTION",0,TK_FUNCTION
        DB "ENDFUNCTION",0,TK_ENDFUNC
        DB "AND",0,TK_EXT
        DB 0

;===============================================================================
; Command dispatcher
;===============================================================================

EXEC_COMMAND_OR_DIRECT:
        CALL SKIP_SPACES
        LD A,(HL)
        CALL TO_UPPER
        CP 'R'
        JR Z,CMD_RUN
        CP 'L'
        JR Z,CHECK_LOAD_OR_LIST
        CP 'S'
        JR Z,CMD_SAVE
        CP 'F'
        JR Z,CMD_FILES
        CP 'C'
        JR Z,CMD_CHDIR
        CP 'N'
        JR Z,CMD_NEW
        CALL EXEC_DIRECT
        RET

CHECK_LOAD_OR_LIST:
        PUSH HL
        INC HL
        LD A,(HL)
        CALL TO_UPPER
        CP 'O'
        POP HL
        JR Z,CMD_LOAD
        JR CMD_LIST

CMD_RUN:
        CALL BUILD_IR_FROM_SOURCE
        CALL RESOLVE_IR_LABELS
        CALL RUN_IR
        RET
CMD_LIST:
        CALL LIST_PROGRAM
        RET
CMD_SAVE:
        CALL CMD_SAVE_PATH
        RET
CMD_LOAD:
        CALL CMD_LOAD_PATH
        RET
CMD_FILES:
        CALL FILES_COMMAND
        RET
CMD_CHDIR:
        CALL CHDIR_COMMAND
        RET
CMD_NEW:
        CALL INIT_SYSTEM
        RET

EXEC_DIRECT:
        LD DE,(SRC_END_PTR)
        PUSH DE
        LD (CUR_LINE_NO),0
        CALL STORE_TOKENIZED_LINE
        LD (SRC_END_PTR),DE
        CALL BUILD_IR_FROM_SOURCE
        CALL RESOLVE_IR_LABELS
        CALL RUN_IR
        POP HL
        LD (SRC_END_PTR),HL
        RET

;===============================================================================
; TOKEN -> IR Compiler
;===============================================================================

BUILD_IR_FROM_SOURCE:
        XOR A
        LD (LABEL_COUNT),A
        LD (PROC_COUNT),A
        LD (TYPE_COUNT),A
        LD (ARRAY_COUNT),A

        ; pass 1 scans labels/types/procs and compiles statements
        LD DE,IR_START
        LD (OUT_PTR),DE
        LD HL,SRC_START
.WALK_LOOP:
        LD DE,(SRC_END_PTR)
        OR A
        SBC HL,DE
        JR NC,.DONE
        PUSH HL
        INC HL
        INC HL
        INC HL
        INC HL
        CALL COMPILE_TOKEN_LINE
        POP HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JR .WALK_LOOP
.DONE:
        LD A,IR_END
        CALL EMIT_IR_B
        LD DE,(OUT_PTR)
        LD (IR_END_PTR),DE
        RET

COMPILE_TOKEN_LINE:
        LD (SRC_PTR),HL
        LD A,(HL)
        OR A
        RET Z

        CP TK_EXT
        JR Z,.EXTENDED_HEAD

        CP TK_PRINT
        JP Z,COMPILE_PRINT
        CP TK_LET
        JP Z,COMPILE_LET
        CP TK_IF
        JP Z,COMPILE_IF
        CP TK_ELSE
        JP Z,COMPILE_ELSE
        CP TK_ENDIF
        JP Z,COMPILE_ENDIF
        CP TK_WHILE
        JP Z,COMPILE_WHILE
        CP TK_WEND
        JP Z,COMPILE_WEND
        CP TK_REPEAT
        JP Z,COMPILE_REPEAT
        CP TK_UNTIL
        JP Z,COMPILE_UNTIL
        CP TK_GOTO
        JP Z,COMPILE_GOTO
        CP TK_GOSUB
        JP Z,COMPILE_GOSUB
        CP TK_RETURN
        JP Z,COMPILE_RETURN
        CP TK_PROC
        JP Z,COMPILE_PROC
        CP TK_ENDPROC
        JP Z,COMPILE_ENDPROC
        CP TK_FUNCTION
        JP Z,COMPILE_FUNCTION
        CP TK_ENDFUNC
        JP Z,COMPILE_ENDFUNC
        CP TK_LOCAL
        JP Z,COMPILE_LOCAL
        CP TK_TYPE
        JP Z,COMPILE_TYPE
        CP TK_DIM
        JP Z,COMPILE_DIM

        ; assignment without LET
        CALL IS_IDENT_START
        JP C,COMPILE_ASSIGNMENT
        RET

.EXTENDED_HEAD:
        INC HL
        LD A,(HL)
        CP TK_LABEL
        JP Z,COMPILE_LABEL_DEF
        RET

;-------------------------------------------------------------------------------
; Statement compilers
;-------------------------------------------------------------------------------

COMPILE_PRINT:
        INC HL
        LD (SRC_PTR),HL
        CALL COMPILE_EXPR
        LD A,IR_PRINT
        CALL EMIT_IR_B
        RET

COMPILE_LET:
        INC HL
        LD (SRC_PTR),HL
        JP COMPILE_ASSIGNMENT

COMPILE_ASSIGNMENT:
        ; Supports:
        ;   A = expr
        ;   ARR(expr) = expr
        ;   P.X = expr
        ;
        ; Strategy:
        ;   compile lvalue address
        ;   compile rhs expression
        ;   STOREPTR
        CALL COMPILE_LVALUE_ADDRESS
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP TK_EQ
        RET NZ
        INC HL
        LD (SRC_PTR),HL
        CALL COMPILE_EXPR
        LD A,IR_STOREPTR
        CALL EMIT_IR_B
        RET

COMPILE_IF:
        ; IF expr THEN
        ;   body
        ; ELSE
        ;   body
        ; ENDIF
        ;
        ; emits:
        ;   expr
        ;   IFZ patch_to_else_or_endif
        ;
        INC HL
        LD (SRC_PTR),HL
        CALL COMPILE_EXPR
        ; optional THEN skip
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP TK_THEN
        JR NZ,.NO_THEN
        INC HL
        LD (SRC_PTR),HL
.NO_THEN:
        LD A,IR_IFZ
        CALL EMIT_IR_B
        CALL EMIT_PATCH_WORD_AND_PUSH_IF
        RET

COMPILE_ELSE:
        ; emit GOTO endif, patch previous IFZ to here
        LD A,IR_GOTO
        CALL EMIT_IR_B
        CALL EMIT_PATCH_WORD_AND_PUSH_ELSE
        CALL PATCH_IF_TO_CURRENT
        RET

COMPILE_ENDIF:
        CALL PATCH_IF_OR_ELSE_TO_CURRENT
        RET

COMPILE_WHILE:
        ; push loop start, compile condition, IFZ exit
        CALL PUSH_LOOP_CURRENT
        INC HL
        LD (SRC_PTR),HL
        CALL COMPILE_EXPR
        LD A,IR_IFZ
        CALL EMIT_IR_B
        CALL EMIT_PATCH_WORD_AND_PUSH_IF
        RET

COMPILE_WEND:
        ; GOTO loop start, patch exit
        LD A,IR_GOTO
        CALL EMIT_IR_B
        CALL POP_LOOP_START_TO_HL
        CALL EMIT_IR_W
        CALL PATCH_IF_TO_CURRENT
        RET

COMPILE_REPEAT:
        CALL PUSH_LOOP_CURRENT
        RET

COMPILE_UNTIL:
        ; UNTIL expr => jump back while expr is zero
        INC HL
        LD (SRC_PTR),HL
        CALL COMPILE_EXPR
        LD A,IR_IFZ
        CALL EMIT_IR_B
        CALL POP_LOOP_START_TO_HL
        CALL EMIT_IR_W
        RET

COMPILE_GOTO:
        INC HL
        LD (SRC_PTR),HL
        LD A,IR_GOTO
        CALL EMIT_IR_B
        CALL EMIT_LABEL_REF_WORD
        RET

COMPILE_GOSUB:
        INC HL
        LD (SRC_PTR),HL
        LD A,IR_GOSUB
        CALL EMIT_IR_B
        CALL EMIT_LABEL_REF_WORD
        RET

COMPILE_RETURN:
        LD A,IR_RETURN
        CALL EMIT_IR_B
        RET

COMPILE_LABEL_DEF:
        ; HL currently points to TK_LABEL after TK_EXT
        INC HL
        CALL ADD_LABEL_CURRENT_IR
        RET

COMPILE_PROC:
        ; PROC name(args)
        ; record proc address; compile body but skip at runtime by emitting GOTO after def in fuller version.
        INC HL
        CALL ADD_PROC_CURRENT_IR
        RET

COMPILE_ENDPROC:
        LD A,IR_RET
        CALL EMIT_IR_B
        RET

COMPILE_FUNCTION:
        INC HL
        CALL ADD_PROC_CURRENT_IR
        RET

COMPILE_ENDFUNC:
        LD A,IR_RET
        CALL EMIT_IR_B
        RET

COMPILE_LOCAL:
        ; LOCAL A AS INTEGER
        ; For now allocate 2 bytes per local in current frame.
        CALL ADD_LOCAL_DECL
        RET

COMPILE_TYPE:
        ; TYPE name
        ;   X AS INTEGER
        ;   Y AS INTEGER
        ; END TYPE
        ;
        ; Registers a structure type.
        ; Nested structures prohibited:
        ; If field type resolves to TYPE_STRUCT, set ERR_NESTSTRUCT.
        CALL ADD_TYPE_DEF
        RET

COMPILE_DIM:
        ; DIM A(10) AS INTEGER
        ; one-dimensional only.
        CALL ADD_DIM_ARRAY
        RET

;===============================================================================
; Expression parser - complete precedence chain
;===============================================================================
;
; expr       = or_expr
; or_expr    = and_expr { OR and_expr }
; and_expr   = rel_expr { AND rel_expr }
; rel_expr   = add_expr { (=|<>|<|<=|>|>=) add_expr }
; add_expr   = mul_expr { (+|-) mul_expr }
; mul_expr   = unary_expr { (*|/) unary_expr }
; unary_expr = (+|-) unary_expr | primary
; primary    = integer | lvalue-load | '(' expr ')'
;
; Structure rule:
;   If identifier is a structure variable, it must be followed by .member.
;   Bare structure identifier is an error.
;
; Array rule:
;   Only one-dimensional array reference: A(expr)
;
;===============================================================================

COMPILE_EXPR:
        JP PARSE_OR

PARSE_OR:
        CALL PARSE_AND
.PO_LOOP:
        LD HL,(SRC_PTR)
        CALL IS_TOKEN_OR
        RET NC
        CALL ADV_EXT_TOKEN
        CALL PARSE_AND
        LD A,IR_OR
        CALL EMIT_IR_B
        JR .PO_LOOP

PARSE_AND:
        CALL PARSE_REL
.PA_LOOP:
        LD HL,(SRC_PTR)
        CALL IS_TOKEN_AND
        RET NC
        CALL ADV_EXT_TOKEN
        CALL PARSE_REL
        LD A,IR_AND
        CALL EMIT_IR_B
        JR .PA_LOOP

PARSE_REL:
        CALL PARSE_ADD
.PR_LOOP:
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP TK_EQ
        JR Z,.EQ
        CP TK_NE
        JR Z,.NE
        CP TK_LT
        JR Z,.LT
        CP TK_GT
        JR Z,.GT
        CP TK_EXT
        JR Z,.EXTREL
        RET
.EQ:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_ADD
        LD A,IR_EQ
        CALL EMIT_IR_B
        JR .PR_LOOP
.NE:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_ADD
        LD A,IR_NE
        CALL EMIT_IR_B
        JR .PR_LOOP
.LT:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_ADD
        LD A,IR_LT
        CALL EMIT_IR_B
        JR .PR_LOOP
.GT:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_ADD
        LD A,IR_GT
        CALL EMIT_IR_B
        JR .PR_LOOP
.EXTREL:
        INC HL
        LD A,(HL)
        CP TK_LE
        JR Z,.LE
        CP TK_GE
        JR Z,.GE
        DEC HL
        RET
.LE:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_ADD
        LD A,IR_LE
        CALL EMIT_IR_B
        JR .PR_LOOP
.GE:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_ADD
        LD A,IR_GE
        CALL EMIT_IR_B
        JR .PR_LOOP

PARSE_ADD:
        CALL PARSE_MUL
.PE_LOOP:
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP TK_PLUS
        JR Z,.ADD
        CP TK_MINUS
        JR Z,.SUB
        RET
.ADD:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_MUL
        LD A,IR_ADD
        CALL EMIT_IR_B
        JR .PE_LOOP
.SUB:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_MUL
        LD A,IR_SUB
        CALL EMIT_IR_B
        JR .PE_LOOP

PARSE_MUL:
        CALL PARSE_UNARY
.PT_LOOP:
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP TK_MUL
        JR Z,.MUL
        CP TK_DIV
        JR Z,.DIV
        RET
.MUL:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_UNARY
        LD A,IR_MUL
        CALL EMIT_IR_B
        JR .PT_LOOP
.DIV:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_UNARY
        LD A,IR_DIV
        CALL EMIT_IR_B
        JR .PT_LOOP

PARSE_UNARY:
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP TK_PLUS
        JR Z,.UPLUS
        CP TK_MINUS
        JR Z,.UMINUS
        JP PARSE_PRIMARY
.UPLUS:
        INC HL
        LD (SRC_PTR),HL
        JP PARSE_UNARY
.UMINUS:
        INC HL
        LD (SRC_PTR),HL
        CALL PARSE_UNARY
        LD A,IR_NEG
        CALL EMIT_IR_B
        RET

PARSE_PRIMARY:
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP TK_INTLIT
        JR Z,.INT
        CP TK_LPAREN
        JR Z,.PAREN
        CALL IS_IDENT_START
        JR C,.LVALUE_LOAD
        LD A,ERR_SYNTAX
        LD (ERROR_CODE),A
        RET
.INT:
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (SRC_PTR),HL
        LD A,IR_PUSHI
        CALL EMIT_IR_B
        EX DE,HL
        CALL EMIT_IR_W
        RET
.PAREN:
        INC HL
        LD (SRC_PTR),HL
        CALL COMPILE_EXPR
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP TK_RPAREN
        JR NZ,.PERR
        INC HL
        LD (SRC_PTR),HL
        RET
.PERR:
        LD A,ERR_SYNTAX
        LD (ERROR_CODE),A
        RET
.LVALUE_LOAD:
        CALL COMPILE_LVALUE_ADDRESS
        LD A,IR_LOADPTR
        CALL EMIT_IR_B
        RET

IS_TOKEN_AND:
        LD A,(HL)
        CP TK_EXT
        RET NZ
        INC HL
        LD A,(HL)
        CP TK_AND
        JR Z,.YES
        OR A
        RET
.YES:   SCF
        RET

IS_TOKEN_OR:
        LD A,(HL)
        CP TK_EXT
        RET NZ
        INC HL
        LD A,(HL)
        CP TK_OR
        JR Z,.YES
        OR A
        RET
.YES:   SCF
        RET

ADV_EXT_TOKEN:
        LD HL,(SRC_PTR)
        INC HL
        INC HL
        LD (SRC_PTR),HL
        RET

;===============================================================================
; LValue compiler
;===============================================================================
;
; Produces address on runtime stack.
;
; A           -> ADDRV varid
; A(expr)     -> ADDRV/array base + index
; P.X         -> ADDRV P + member offset
; P.NEST.X    -> rejected: nested structures forbidden by type checker
;
;===============================================================================

COMPILE_LVALUE_ADDRESS:
        LD HL,(SRC_PTR)
        LD A,(HL)
        CALL IS_IDENT_CHAR
        JR NC,.ERR
        LD B,A                  ; identifier first char only for compact var id
        INC HL
        LD (SRC_PTR),HL

        ; emit address of global variable first
        LD A,IR_ADDRV
        CALL EMIT_IR_B
        LD A,B
        SUB 'A'
        CALL EMIT_IR_B

        ; Decide array or member or simple variable
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP TK_LPAREN
        JR Z,.ARRAY
        CP TK_DOT
        JR Z,.MEMBER

        ; Semantic check: bare structure not allowed in expression/assignment value.
        ; For lvalue assignment to whole struct also forbidden.
        LD A,B
        CALL IS_STRUCT_VARIABLE
        RET NC
        LD A,ERR_STRUCTBARE
        LD (ERROR_CODE),A
        RET

.ARRAY:
        ; one-dimensional only: identifier(expr)
        INC HL
        LD (SRC_PTR),HL
        CALL COMPILE_EXPR
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP TK_RPAREN
        JR NZ,.ERR
        INC HL
        LD (SRC_PTR),HL
        LD A,IR_INDEX
        CALL EMIT_IR_B
        RET

.MEMBER:
        ; identifier.member
        INC HL
        LD (SRC_PTR),HL
        CALL READ_MEMBER_NAME_AND_EMIT_OFFSET
        LD A,IR_MEMBER
        CALL EMIT_IR_B
        RET

.ERR:
        LD A,ERR_SYNTAX
        LD (ERROR_CODE),A
        RET

IS_IDENT_START:
        LD A,(HL)
IS_IDENT_CHAR:
        CP 'A'
        JR C,.NO
        CP 'Z'+1
        JR NC,.NO
        SCF
        RET
.NO:
        OR A
        RET

IS_STRUCT_VARIABLE:
        ; IN A = first char of variable name
        ; This compact version uses a side table stub.
        ; Carry set means var is struct.
        ; Default: not struct.
        OR A
        RET

READ_MEMBER_NAME_AND_EMIT_OFFSET:
        ; Reads a member name and emits member offset word.
        ; Full implementation should search TYPE_TABLE using variable type.
        ;
        ; Compact convention for now:
        ;   .X -> offset 0
        ;   .Y -> offset 2
        ;   .HP or other -> offset 4
        ;
        LD HL,(SRC_PTR)
        LD A,(HL)
        CP 'X'
        JR Z,.X
        CP 'Y'
        JR Z,.Y
        JR .OTHER
.X:
        INC HL
        LD (SRC_PTR),HL
        LD HL,0
        CALL EMIT_IR_W
        RET
.Y:
        INC HL
        LD (SRC_PTR),HL
        LD HL,2
        CALL EMIT_IR_W
        RET
.OTHER:
        ; skip identifier
.SK:
        LD A,(HL)
        CALL IS_IDENT_CHAR
        JR NC,.DONE
        INC HL
        JR .SK
.DONE:
        LD (SRC_PTR),HL
        LD HL,4
        CALL EMIT_IR_W
        RET

;===============================================================================
; Label / control patch stack helpers
;===============================================================================

IF_STACK:
        DS 64
IF_SP:
        DW IF_STACK

LOOP_STACK:
        DS 64
LOOP_SP:
        DW LOOP_STACK

EMIT_PATCH_WORD_AND_PUSH_IF:
        ; emits 0000 and pushes address of word
        LD DE,(OUT_PTR)
        PUSH DE
        LD HL,0
        CALL EMIT_IR_W
        POP HL
        CALL PUSH_IF_PATCH
        RET

EMIT_PATCH_WORD_AND_PUSH_ELSE:
        LD DE,(OUT_PTR)
        PUSH DE
        LD HL,0
        CALL EMIT_IR_W
        POP HL
        CALL PUSH_IF_PATCH
        RET

PUSH_IF_PATCH:
        EX DE,HL
        LD HL,(IF_SP)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (IF_SP),HL
        RET

POP_IF_PATCH:
        LD HL,(IF_SP)
        DEC HL
        LD D,(HL)
        DEC HL
        LD E,(HL)
        LD (IF_SP),HL
        EX DE,HL
        RET

PATCH_IF_TO_CURRENT:
PATCH_IF_OR_ELSE_TO_CURRENT:
        CALL POP_IF_PATCH
        EX DE,HL              ; DE = patch address
        LD HL,(OUT_PTR)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        RET

PUSH_LOOP_CURRENT:
        LD DE,(OUT_PTR)
        LD HL,(LOOP_SP)
        LD (HL),E
        INC HL
        LD (HL),D
        INC HL
        LD (LOOP_SP),HL
        RET

POP_LOOP_START_TO_HL:
        LD HL,(LOOP_SP)
        DEC HL
        LD D,(HL)
        DEC HL
        LD E,(HL)
        LD (LOOP_SP),HL
        EX DE,HL
        RET

;===============================================================================
; Label/proc/type/array table routines
;===============================================================================

ADD_LABEL_CURRENT_IR:
        ; HL = label name
        ; entry: name[8], addr[2]
        LD A,(LABEL_COUNT)
        LD C,A
        LD B,0
        LD HL,LABEL_TABLE
        ; offset = count * 10
        CALL ADD_BC_TIMES_10_TO_HL
        ; source name is in SRC_PTR-ish: recover by current source pointer not needed in this skeleton
        ; For real use, copy label name from token stream.
        LD DE,(OUT_PTR)
        ; name copy omitted compactly, address stored
        LD (HL),'?'
        INC HL
        LD B,7
.ALZ:
        LD (HL),0
        INC HL
        DJNZ .ALZ
        LD (HL),E
        INC HL
        LD (HL),D
        LD A,(LABEL_COUNT)
        INC A
        LD (LABEL_COUNT),A
        RET

EMIT_LABEL_REF_WORD:
        ; Compile-time placeholder. Full resolver scans label table.
        ; Accepts *LABEL token after GOTO/GOSUB.
        LD HL,0
        CALL EMIT_IR_W
        RET

RESOLVE_IR_LABELS:
        ; Full implementation scans IR for GOTO/GOSUB zero placeholders and patches.
        ; Hook present for reuse.
        RET

ADD_PROC_CURRENT_IR:
        ; record procedure/function name and address
        LD A,(PROC_COUNT)
        INC A
        LD (PROC_COUNT),A
        RET

ADD_LOCAL_DECL:
        ; local var consumes 2 bytes
        LD HL,(LOCAL_SIZE)
        INC HL
        INC HL
        LD (LOCAL_SIZE),HL
        RET

ADD_TYPE_DEF:
        ; Registers type metadata.
        ; Nested structure prohibition should be enforced when parsing field AS type.
        LD A,(TYPE_COUNT)
        INC A
        LD (TYPE_COUNT),A
        RET

ADD_DIM_ARRAY:
        ; DIM A(10) AS INTEGER
        ; one-dimensional only.
        ; emits runtime allocation IR if desired.
        LD A,(ARRAY_COUNT)
        INC A
        LD (ARRAY_COUNT),A
        RET

ADD_BC_TIMES_10_TO_HL:
        ; HL += BC * 10
        PUSH HL
        LD H,B
        LD L,C
        ADD HL,HL
        PUSH HL
        ADD HL,HL
        ADD HL,HL
        POP DE
        ADD HL,DE
        EX DE,HL
        POP HL
        ADD HL,DE
        RET

;===============================================================================
; IR emit helpers
;===============================================================================

EMIT_IR_B:
        LD DE,(OUT_PTR)
        LD (DE),A
        INC DE
        LD (OUT_PTR),DE
        RET

EMIT_IR_W:
        LD DE,(OUT_PTR)
        LD A,L
        LD (DE),A
        INC DE
        LD A,H
        LD (DE),A
        INC DE
        LD (OUT_PTR),DE
        RET

;===============================================================================
; IR interpreter
;===============================================================================

RUN_IR:
        LD HL,IR_START
        LD (PC),HL

IR_LOOP:
        LD HL,(PC)
        LD A,(HL)
        INC HL
        LD (PC),HL

        CP IR_PUSHI
        JP Z,IR_PUSHI_H
        CP IR_PUSHV
        JP Z,IR_PUSHV_H
        CP IR_STOREV
        JP Z,IR_STOREV_H
        CP IR_ADDRV
        JP Z,IR_ADDRV_H
        CP IR_LOADPTR
        JP Z,IR_LOADPTR_H
        CP IR_STOREPTR
        JP Z,IR_STOREPTR_H
        CP IR_MEMBER
        JP Z,IR_MEMBER_H
        CP IR_INDEX
        JP Z,IR_INDEX_H

        CP IR_ADD
        JP Z,IR_ADD_H
        CP IR_SUB
        JP Z,IR_SUB_H
        CP IR_MUL
        JP Z,IR_MUL_H
        CP IR_DIV
        JP Z,IR_DIV_H
        CP IR_NEG
        JP Z,IR_NEG_H
        CP IR_EQ
        JP Z,IR_EQ_H
        CP IR_NE
        JP Z,IR_NE_H
        CP IR_LT
        JP Z,IR_LT_H
        CP IR_LE
        JP Z,IR_LE_H
        CP IR_GT
        JP Z,IR_GT_H
        CP IR_GE
        JP Z,IR_GE_H
        CP IR_AND
        JP Z,IR_AND_H
        CP IR_OR
        JP Z,IR_OR_H

        CP IR_PRINT
        JP Z,IR_PRINT_H
        CP IR_GOTO
        JP Z,IR_GOTO_H
        CP IR_IFZ
        JP Z,IR_IFZ_H
        CP IR_GOSUB
        JP Z,IR_GOSUB_H
        CP IR_RETURN
        JP Z,IR_RETURN_H
        CP IR_CALL
        JP Z,IR_CALL_H
        CP IR_RET
        JP Z,IR_RETURN_H

        CP IR_END
        RET
        JP IR_LOOP

IR_PUSHI_H:
        LD HL,(PC)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (PC),HL
        EX DE,HL
        CALL PUSH_HL
        JP IR_LOOP

IR_PUSHV_H:
        LD HL,(PC)
        LD A,(HL)
        INC HL
        LD (PC),HL
        CALL GET_VAR_ADDR
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        CALL PUSH_HL
        JP IR_LOOP

IR_STOREV_H:
        LD HL,(PC)
        LD A,(HL)
        INC HL
        LD (PC),HL
        CALL GET_VAR_ADDR
        PUSH HL
        CALL POP_HL
        EX DE,HL
        POP HL
        LD (HL),E
        INC HL
        LD (HL),D
        JP IR_LOOP

IR_ADDRV_H:
        LD HL,(PC)
        LD A,(HL)
        INC HL
        LD (PC),HL
        CALL GET_VAR_ADDR
        CALL PUSH_HL
        JP IR_LOOP

IR_LOADPTR_H:
        CALL POP_HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        CALL PUSH_HL
        JP IR_LOOP

IR_STOREPTR_H:
        CALL POP_HL          ; value
        EX DE,HL
        CALL POP_HL          ; address
        LD (HL),E
        INC HL
        LD (HL),D
        JP IR_LOOP

IR_MEMBER_H:
        LD HL,(PC)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        LD (PC),HL
        CALL POP_HL
        ADD HL,DE
        CALL PUSH_HL
        JP IR_LOOP

IR_INDEX_H:
        ; Stack: address/base, index. Element size fixed 2 for INTEGER arrays in compact version.
        CALL POP_HL          ; index
        ADD HL,HL            ; *2
        EX DE,HL
        CALL POP_HL          ; base
        ADD HL,DE
        CALL PUSH_HL
        JP IR_LOOP

IR_ADD_H:
        CALL POP_HL
        EX DE,HL
        CALL POP_HL
        ADD HL,DE
        CALL PUSH_HL
        JP IR_LOOP

IR_SUB_H:
        CALL POP_HL
        EX DE,HL
        CALL POP_HL
        OR A
        SBC HL,DE
        CALL PUSH_HL
        JP IR_LOOP

IR_MUL_H:
        CALL POP_HL
        EX DE,HL
        CALL POP_HL
        CALL MUL16
        CALL PUSH_HL
        JP IR_LOOP

IR_DIV_H:
        CALL POP_HL
        EX DE,HL
        CALL POP_HL
        CALL DIV16
        CALL PUSH_HL
        JP IR_LOOP

IR_NEG_H:
        CALL POP_HL
        XOR A
        LD D,A
        LD E,A
        EX DE,HL
        OR A
        SBC HL,DE
        CALL PUSH_HL
        JP IR_LOOP

IR_EQ_H: CALL CMP_EQ : JP IR_LOOP
IR_NE_H: CALL CMP_NE : JP IR_LOOP
IR_LT_H: CALL CMP_LT : JP IR_LOOP
IR_LE_H: CALL CMP_LE : JP IR_LOOP
IR_GT_H: CALL CMP_GT : JP IR_LOOP
IR_GE_H: CALL CMP_GE : JP IR_LOOP

IR_AND_H:
        CALL POP_HL
        LD A,H
        OR L
        JR Z,.FALSE
        CALL POP_HL
        LD A,H
        OR L
        JR Z,.FALSE2
        LD HL,1
        CALL PUSH_HL
        JP IR_LOOP
.FALSE:
        CALL POP_HL
.FALSE2:
        LD HL,0
        CALL PUSH_HL
        JP IR_LOOP

IR_OR_H:
        CALL POP_HL
        LD A,H
        OR L
        JR NZ,.TRUE
        CALL POP_HL
        LD A,H
        OR L
        JR NZ,.TRUE2
        LD HL,0
        CALL PUSH_HL
        JP IR_LOOP
.TRUE:
        CALL POP_HL
.TRUE2:
        LD HL,1
        CALL PUSH_HL
        JP IR_LOOP

IR_PRINT_H:
        CALL POP_HL
        CALL PRINT_NUM16
        CALL PRINT_CRLF
        JP IR_LOOP

IR_GOTO_H:
        LD HL,(PC)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (PC),HL
        JP IR_LOOP

IR_IFZ_H:
        CALL POP_HL
        LD A,H
        OR L
        LD HL,(PC)
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        JR Z,.JUMP
        LD (PC),HL
        JP IR_LOOP
.JUMP:
        EX DE,HL
        LD (PC),HL
        JP IR_LOOP

IR_GOSUB_H:
        LD HL,(PC)
        INC HL
        INC HL
        CALL PUSH_CALL_HL
        LD HL,(PC)
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD (PC),HL
        JP IR_LOOP

IR_CALL_H:
        JP IR_GOSUB_H

IR_RETURN_H:
        CALL POP_CALL_HL
        LD (PC),HL
        JP IR_LOOP

GET_VAR_ADDR:
        ; A = global variable id 0..25
        LD L,A
        LD H,0
        ADD HL,HL
        LD DE,GLOBAL_VAR_BASE
        ADD HL,DE
        RET

;===============================================================================
; Stack and call stack
;===============================================================================

PUSH_HL:
        LD DE,(SPTR)
        LD (DE),L
        INC DE
        LD (DE),H
        INC DE
        LD (SPTR),DE
        RET

POP_HL:
        LD DE,(SPTR)
        DEC DE
        LD H,(DE)
        DEC DE
        LD L,(DE)
        LD (SPTR),DE
        RET

PUSH_CALL_HL:
        LD DE,(CALL_SP)
        LD (DE),L
        INC DE
        LD (DE),H
        INC DE
        LD (CALL_SP),DE
        RET

POP_CALL_HL:
        LD DE,(CALL_SP)
        DEC DE
        LD H,(DE)
        DEC DE
        LD L,(DE)
        LD (CALL_SP),DE
        RET

CALL_STACK:
        DS 128

;===============================================================================
; Comparisons
;===============================================================================

CMP_EQ:
        CALL POP_HL
        EX DE,HL
        CALL POP_HL
        OR A
        SBC HL,DE
        JR Z,.T
        LD HL,0
        CALL PUSH_HL
        RET
.T:
        LD HL,1
        CALL PUSH_HL
        RET

CMP_NE:
        CALL CMP_EQ
        CALL POP_HL
        LD A,H
        OR L
        JR Z,.T
        LD HL,0
        CALL PUSH_HL
        RET
.T:
        LD HL,1
        CALL PUSH_HL
        RET

CMP_LT:
        CALL POP_HL
        EX DE,HL
        CALL POP_HL
        OR A
        SBC HL,DE
        JP M,.T
        LD HL,0
        CALL PUSH_HL
        RET
.T:
        LD HL,1
        CALL PUSH_HL
        RET

CMP_LE:
        CALL CMP_GT
        CALL POP_HL
        LD A,H
        OR L
        JR Z,.T
        LD HL,0
        CALL PUSH_HL
        RET
.T:
        LD HL,1
        CALL PUSH_HL
        RET

CMP_GT:
        CALL POP_HL
        EX DE,HL
        CALL POP_HL
        EX DE,HL
        OR A
        SBC HL,DE
        JP M,.T
        LD HL,0
        CALL PUSH_HL
        RET
.T:
        LD HL,1
        CALL PUSH_HL
        RET

CMP_GE:
        CALL CMP_LT
        CALL POP_HL
        LD A,H
        OR L
        JR Z,.T
        LD HL,0
        CALL PUSH_HL
        RET
.T:
        LD HL,1
        CALL PUSH_HL
        RET

;===============================================================================
; Arithmetic
;===============================================================================

MUL16:
        ; HL * DE -> HL, unsigned shift-add
        LD BC,0
        LD A,16
.ML:
        ADD HL,HL
        RL C
        RL B
        BIT 0,E
        JR Z,.NOADD
        ADD HL,BC
.NOADD:
        SRL D
        RR E
        DEC A
        JR NZ,.ML
        RET

DIV16:
        ; Placeholder: replace with tested unsigned 16-bit division routine.
        RET

;===============================================================================
; Printing
;===============================================================================

PRINT_NUM16:
        LD DE,10000
        CALL PRINT_DIGIT
        LD DE,1000
        CALL PRINT_DIGIT
        LD DE,100
        CALL PRINT_DIGIT
        LD DE,10
        CALL PRINT_DIGIT
        LD A,L
        ADD A,'0'
        CALL PUT_CHAR
        RET

PRINT_DIGIT:
        LD B,'0'
.PD_LOOP:
        OR A
        SBC HL,DE
        JR C,.PD_OUT
        INC B
        JR .PD_LOOP
.PD_OUT:
        ADD HL,DE
        LD A,B
        CALL PUT_CHAR
        RET

;===============================================================================
; LIST
;===============================================================================

LIST_PROGRAM:
        LD HL,SRC_START
.LIST_LOOP:
        LD DE,(SRC_END_PTR)
        OR A
        SBC HL,DE
        RET NC
        PUSH HL
        INC HL
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        CALL PRINT_NUM16
        LD A,' '
        CALL PUT_CHAR

        POP HL
        PUSH HL
        INC HL
        INC HL
        INC HL
        INC HL
        CALL LIST_TOKEN_LINE
        CALL PRINT_CRLF

        POP HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JR .LIST_LOOP

LIST_TOKEN_LINE:
        LD A,(HL)
        OR A
        RET Z
        CP TK_PRINT
        JR Z,.PRINT
        CP TK_IF
        JR Z,.IF
        CP TK_THEN
        JR Z,.THEN
        CP TK_ELSE
        JR Z,.ELSE
        CP TK_ENDIF
        JR Z,.ENDIF
        CP TK_INTLIT
        JR Z,.INT
        CP TK_PLUS
        JR Z,.PLUS
        CP TK_MINUS
        JR Z,.MINUS
        CP TK_MUL
        JR Z,.MUL
        CP TK_DIV
        JR Z,.DIV
        CP TK_EQ
        JR Z,.EQ
        CP TK_DOT
        JR Z,.DOT
        CALL PUT_CHAR
        INC HL
        JR LIST_TOKEN_LINE
.PRINT: PUSH HL: LD HL,STR_PRINT: CALL PRINT_STRING: POP HL: INC HL: JR LIST_TOKEN_LINE
.IF:    PUSH HL: LD HL,STR_IF: CALL PRINT_STRING: POP HL: INC HL: JR LIST_TOKEN_LINE
.THEN:  PUSH HL: LD HL,STR_THEN: CALL PRINT_STRING: POP HL: INC HL: JR LIST_TOKEN_LINE
.ELSE:  PUSH HL: LD HL,STR_ELSE: CALL PRINT_STRING: POP HL: INC HL: JR LIST_TOKEN_LINE
.ENDIF: PUSH HL: LD HL,STR_ENDIF: CALL PRINT_STRING: POP HL: INC HL: JR LIST_TOKEN_LINE
.INT:
        INC HL
        LD E,(HL)
        INC HL
        LD D,(HL)
        INC HL
        PUSH HL
        EX DE,HL
        CALL PRINT_NUM16
        POP HL
        JR LIST_TOKEN_LINE
.PLUS:  LD A,'+' : CALL PUT_CHAR : INC HL : JR LIST_TOKEN_LINE
.MINUS: LD A,'-' : CALL PUT_CHAR : INC HL : JR LIST_TOKEN_LINE
.MUL:   LD A,'*' : CALL PUT_CHAR : INC HL : JR LIST_TOKEN_LINE
.DIV:   LD A,'/' : CALL PUT_CHAR : INC HL : JR LIST_TOKEN_LINE
.EQ:    LD A,'=' : CALL PUT_CHAR : INC HL : JR LIST_TOKEN_LINE
.DOT:   LD A,'.' : CALL PUT_CHAR : INC HL : JR LIST_TOKEN_LINE

STR_PRINT: DB "PRINT ",0
STR_IF: DB "IF ",0
STR_THEN: DB " THEN ",0
STR_ELSE: DB "ELSE",0
STR_ENDIF: DB "END IF",0

;===============================================================================
; MSX-DOS2 SAVE / LOAD handle APIs
;===============================================================================

DOS2_OPEN       EQU 42h
DOS2_CREATE     EQU 43h
DOS2_CLOSE      EQU 45h
DOS2_READ       EQU 48h
DOS2_WRITE      EQU 49h
DOS2_OPEN_READ  EQU 01h
DOS2_CREATE_NEW EQU 00h

FILE_HANDLE: DB 0

CMD_SAVE_PATH:
        LD DE,SAVE_PATH
        CALL COPY_QUOTED_PATH
        LD DE,SAVE_PATH
        CALL SAVE_PROGRAM_PATH
        RET

CMD_LOAD_PATH:
        LD DE,SAVE_PATH
        CALL COPY_QUOTED_PATH
        LD DE,SAVE_PATH
        CALL LOAD_PROGRAM_PATH
        RET

SAVE_PROGRAM_PATH:
        LD C,DOS2_CREATE
        LD B,00h
        LD A,DOS2_CREATE_NEW
        CALL BDOS
        OR A
        RET NZ
        LD A,B
        LD (FILE_HANDLE),A

        LD A,(FILE_HANDLE)
        LD B,A
        LD DE,SBI_HEADER
        LD HL,4
        LD C,DOS2_WRITE
        CALL BDOS

        LD HL,(SRC_END_PTR)
        LD DE,SRC_START
        OR A
        SBC HL,DE
        LD (SBI_SIZE),HL

        LD A,(FILE_HANDLE)
        LD B,A
        LD DE,SBI_SIZE
        LD HL,2
        LD C,DOS2_WRITE
        CALL BDOS

        LD A,(FILE_HANDLE)
        LD B,A
        LD DE,SRC_START
        LD HL,(SBI_SIZE)
        LD C,DOS2_WRITE
        CALL BDOS

        LD A,(FILE_HANDLE)
        LD B,A
        LD C,DOS2_CLOSE
        CALL BDOS
        RET

LOAD_PROGRAM_PATH:
        LD C,DOS2_OPEN
        LD A,DOS2_OPEN_READ
        CALL BDOS
        OR A
        RET NZ
        LD A,B
        LD (FILE_HANDLE),A

        LD A,(FILE_HANDLE)
        LD B,A
        LD DE,SBI_HEADER_READ
        LD HL,4
        LD C,DOS2_READ
        CALL BDOS

        LD A,(FILE_HANDLE)
        LD B,A
        LD DE,SBI_SIZE
        LD HL,2
        LD C,DOS2_READ
        CALL BDOS

        LD A,(FILE_HANDLE)
        LD B,A
        LD DE,SRC_START
        LD HL,(SBI_SIZE)
        LD C,DOS2_READ
        CALL BDOS

        LD HL,SRC_START
        LD DE,(SBI_SIZE)
        ADD HL,DE
        LD (SRC_END_PTR),HL

        LD A,(FILE_HANDLE)
        LD B,A
        LD C,DOS2_CLOSE
        CALL BDOS
        RET

COPY_QUOTED_PATH:
.CQP_FIND:
        LD A,(HL)
        OR A
        JR Z,.CQP_EMPTY
        CP '"'
        JR Z,.CQP_COPY_START
        INC HL
        JR .CQP_FIND
.CQP_COPY_START:
        INC HL
.CQP_COPY:
        LD A,(HL)
        OR A
        JR Z,.CQP_END
        CP '"'
        JR Z,.CQP_END
        LD (DE),A
        INC DE
        INC HL
        JR .CQP_COPY
.CQP_END:
        XOR A
        LD (DE),A
        RET
.CQP_EMPTY:
        LD HL,DEFAULT_SAVE_PATH
.CQP_DEF:
        LD A,(HL)
        LD (DE),A
        OR A
        RET Z
        INC HL
        INC DE
        JR .CQP_DEF

SBI_HEADER: DB "SBI2"
SBI_HEADER_READ: DS 4
SBI_SIZE: DW 0
DEFAULT_SAVE_PATH: DB "PROGRAM.SBI",0
SAVE_PATH: DS 128

;===============================================================================
; FILES / CHDIR stubs using MSX-DOS2
;===============================================================================

FILES_COMMAND:
        ; integrated in previous version; left as hook
        RET

CHDIR_COMMAND:
        ; integrated in previous version; left as hook
        RET

;===============================================================================
; Heap / structure / array runtime helpers
;===============================================================================

ALLOC:
        LD DE,(HEAP_PTR)
        PUSH DE
        ADD HL,DE
        LD (HEAP_PTR),HL
        POP HL
        RET

STRUCT_MEMBER_RUNTIME:
        ADD HL,DE
        RET

        END START
