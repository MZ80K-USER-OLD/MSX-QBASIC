; ------------------------------------------------------------------------------
; BBX80 MSX HOST v1.0
; Copyright (C) 2024 H.J. Berends
;
; ver2.0 for MSX2 mcheine
; Copyright (C) 2027 MZ80K-USER-OLD
;
; You can freely use, distribute or modify this program.
; It is provided freely and "as it is" in the hope that it will be useful, 
; but without any warranty of any kind, either expressed or implied.
; ------------------------------------------------------------------------------

		SECTION MSXHOST

		PUBLIC	msxBIOS
		PUBLIC	msxKey
		PUBLIC	msxSetCliksw
		PUBLIC	msxInitText
		PUBLIC	msxBeep
		PUBLIC	msxINITXT80
		PUBLIC	msxINITXT
		PUBLIC	msxCLS
		PUBLIC	msxSTRPUT
		PUBLIC  msxCHPUT
		PUBLIC	msxPINLINE
		PUBLIC  msxPOSIT
		PUBLIC	msxGETPOS
		PUBLIC	msxCheckMSX2
		;


IFNDEF BDOS
BDOS		EQU	$0005			; MSX-DOS API CALL
ENDIF
; ------------------------------------------------------------------------------
;  MSX BIOS entries
;
CALSLT		EQU	$001C
IDBYT0		EQU	$002B
INITXT		EQU	$006C			; select screen mode 0
INIT32		EQU	$006F			; select screen mode 1
CHSNS   	EQU $009C
CHGET   	EQU $009F    		; 1文字入力
CHPUT   	EQU $00A2    		; 1文字出力
BEEP		EQU	$00C0
POSIT		EQU $00C6    		; カーソル位置指定
CLS		    EQU $00C3    		; 画面消去
PINLINE		EQU $00AE           ; 一行入力

BUFMIN		EQU $F55D           ; 入力バッファ-1
BUF		    EQU $F55E           ; BASIC 入力バッファ、終端が0
CLIKSW		EQU	$F3DB
EXPTBL		EQU	$FCC1			; スロットテーブル

LINL40		EQU	0F3AEH			; screen width mode 0
LINL32		EQU	0F3AFH			; screen width mode 1
LINLEN		EQU	0F3B0H			; screen width
CSRY		EQU 0F3DCH			; cursor row position
CSRX		EQU	0F3DDH			; cursor column position
EXBRSA		EQU	0FAF8H			; slotid subrom

; ------------------------------------------------------------------------------
; Use MSX BIOS keyboard input which is faster than via CP/M dosKey routine.
; ------------------------------------------------------------------------------
msxKey:		PUSH	IX
		LD	IX,CHSNS	; Test the status of the keyboard buffer
		CALL	msxBIOS
		JR	Z,_endKey	; Z = no key is pressed
		LD	IX,CHGET	; 
		CALL	msxBIOS
_endKey:	POP	IX
		RET

; ------------------------------------------------------------------------------
; Set keyboard click switch
; ------------------------------------------------------------------------------
msxSetCliksw:	AND	$01		; 0=Off 1=On
		LD	(CLIKSW),A
		RET

; ------------------------------------------------------------------------------
; Initialize text mode (screen 0), uses current screen width setting (LINL40)
; ------------------------------------------------------------------------------
msxInitText:
		PUSH	IX
		LD	IX,INITXT
		CALL	msxBIOS
		POP	IX
		RET
; ------------------------------------------------------------------------------
; CURSOR POSITION
; L  = Y
; H  = X 
; ------------------------------------------------------------------------------		
msxPOSIT:
		PUSH IX
		LD IX,POSIT       ; HLレジスタの値を画面に反映
		CALL msxBIOS
		POP IX
		RET

; ------------------------------------------------------------------------------
; GET CURSOR POSITION
; L  = Y
; H  = X 
; ------------------------------------------------------------------------------		
msxGETPOS:
   	 ; 現在のシステム変数からカーソル位置を取得
    	LD  A,(CSRX)
    	LD  H,A
    	LD  A,(CSRY)
    	LD  L,A
		RET

; ------------------------------------------------------------------------------
; Output Bell / MSX Beep
; CHPUT BELL only works when the VDP is in text mode, use BIOS call instead
; ------------------------------------------------------------------------------
msxBeep:
		PUSH	IX
		LD	IX,BEEP
		CALL	msxBIOS
		POP	IX
		RET
;
; Output String terminated 0
; HL
;
msxSTRPUT:
		LD  A,(HL)
		OR  A
		RET Z
		INC HL
		PUSH HL
		LD	IX,CHPUT      
		CALL msxBIOS	
		POP HL
		JR msxSTRPUT
;
; Output Character
; A=Character
;
msxCHPUT:
		PUSH IX
		LD	IX,CHPUT      
		CALL msxBIOS
		POP IX	
		RET

;
; Input line
;  INPUT:Nothing
;  OUTPUT: HL=Address of input buffer
;  CY:CTRL-STOP
;
msxPINLINE:
		PUSH IX
		LD	IX,PINLINE   ; 一行入力
		CALL msxBIOS
		INC HL
		POP IX	
		RET            ; CTRL-STOPが押されたらCY=1	

; Init Screen   
;  Screen 0, width 40
;
msxINITXT:
		PUSH  IX
		LD  A,40
		LD	(LINL40),A		; set 40 column width
		LD	IX,INITXT
		CALL msxBIOS
		POP IX
		RET
;
; Init Screen   
;  Screen 0, width 80
;
msxINITXT80:
		PUSH  IX
		LD  A,80
		LD	(LINL40),A		; set 80 column width
		LD	IX,INITXT
		CALL msxBIOS
		POP IX
		RET
;
;	Screen Clear
;
msxCLS:
		PUSH IX
		LD	IX,CLS
		CALL msxBIOS
		POP IX
		RET		

;------------------------------------------------------------------------------
; Check Msx Version (MSX2 or over)
; On MSX1, print message and exit to OS
; ------------------------------------------------------------------------------
msxCheckMSX2:
		LD	A,(EXBRSA)	; MSX2 Version
		OR	A			; MSX1 ?
		JP	Z,ERRMSX1	; yep, invalid parameter
		RET				; CY=0

ERRMSX1:	
		LD	DE, msg
		LD	C, $09
		CALL BDOS		; OS SYSTEM CALL
		LD C,$00
		CALL BDOS		; EXIT TO OS

msg:	db	"You need MSX2 or over",0DH,0AH,"$"

; ------------------------------------------------------------------------------
; MSX BIOS routines, interslot call wrapper
; Parameters: 
;   IX = BIOS routine
; ------------------------------------------------------------------------------
msxBIOS:
		PUSH 	IY
		LD	IY,(EXPTBL-1)	; BIOS slot in IYH

		; Save shadow registers
		EXX			
		PUSH	BC
		PUSH	DE
		PUSH	HL
		EXX

		CALL	CALSLT		; interslot call
		
		; Restore shadow registers
		EXX
		POP	HL
		POP	DE
		POP	BC
		EXX
		
		POP	IY
		RET

