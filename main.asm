;CKOPT 1, CKSEL3:1	111, CKSEL0 1, SUT1:0	01
.def	var	=	r16
.def	xorReg = r17
.def	delayReg1 = r18
.def	delayReg2 = r19
.def	delayReg3 = r20
.def	count = r21
.def	zeichen = r22

.equ F_CPU = 4000000                            ; Systemtakt in Hz
.equ BAUD  = 9600                               ; Baudrate

; Berechnungen
.equ UBRR_VAL   = ((F_CPU+BAUD*8)/(BAUD*16)-1)  ; clever runden
.equ BAUD_REAL  = (F_CPU/(16*(UBRR_VAL+1)))      ; Reale Baudrate
.equ BAUD_ERROR = ((BAUD_REAL*1000)/BAUD-1000)  ; Fehler in Promille

.if ((BAUD_ERROR>10) || (BAUD_ERROR<-10))       ; max. +/-10 Promille Fehler
  .error "Systematischer Fehler der Baudrate gr�sser 1 Prozent und damit zu hoch!"
.endif


init:
	ldi		var,	low(RAMEND) ; init the stack pointer for rcall
	out		spl,	var
	ldi		var,	high(RAMEND)
	out		sph,	var

	ldi		xorReg,	0b00100000
	;ldi		zeroReg, 0x00

	ldi		var,	0b00100000
	out		DDRD,	var		;Configure Port D5 as output

	;ldi		var,	0x00
	;out		DDRC,	var		;Configure Ports C as input

	ldi		var,	0b10000000
	out		PORTD,	var		;Enable Pull Up resistor on Port D7

	ldi		var,	0b10100000
	;ldi		var,	0x00
	;ldi		var,	0b00000000
	out		PORTD,	var		; Turn LED on Port D5 on


	; Baudrate einstellen

    ldi     var, HIGH(UBRR_VAL)
    out     UBRRH, var
    ldi     var, LOW(UBRR_VAL)
    out     UBRRL, var

    ; Frame-Format: 8 Bit

    ldi     var, (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
    out     UCSRC, var

    sbi     UCSRB,TXEN                  ; TX aktivieren

mainloop:
	sbic	PIND,	7	; skip next if Input 7 is not active
	rjmp	mainloop

	ldi		count,	5


	rcall	btTest


	again:
	rcall	blink
	dec		count
	brne	again

	rjmp	held


btTest:
    ldi     zeichen, 'T'
    rcall   serout
    ldi     zeichen, 'e'
    rcall   serout
    ldi     zeichen, 's'
    rcall   serout
    ldi     zeichen, 't'
    rcall   serout
    ldi     zeichen, '!'
    rcall   serout
	ldi     zeichen, ' '
    rcall   serout
    ldi     zeichen, 'v'
    rcall   serout
    ldi     zeichen, 'o'
    rcall   serout
    ldi     zeichen, 'n'
    rcall   serout
    ldi     zeichen, ' '
    rcall   serout
	ldi     zeichen, 'M'
    rcall   serout
    ldi     zeichen, 'i'
    rcall   serout
    ldi     zeichen, 'l'
    rcall   serout
    ldi     zeichen, 'a'
    rcall   serout
    ldi     zeichen, 'n'
    rcall   serout
    ldi     zeichen, 10
    rcall   serout
    ;ldi     zeichen, 13
    ;rcall   serout
    ;rcall   sync                        
    ret

serout:
    sbis    UCSRA,UDRE                  ; Warten bis UDR f�r das n�chste
                                        ; Byte bereit ist
    rjmp    serout
    out     UDR, zeichen
    ret

blink:
	;enable led
	sbi		PORTD,	5
	
	;delay for a little while
	ldi		delayReg1,	1
	ldi		delayReg2,	0
	ldi		delayReg3,	0
	rcall	delay

	;disable led
	cbi		PORTD,	5

	;delay for a long while
	ldi		delayReg1,	3
	ldi		delayReg2,	0
	ldi		delayReg3,	0
	rcall	delay
	ret


held:
	sbis	PIND,		7		; skip next if Input 7 is active
	rjmp	held
	ldi		delayReg1,	0x01
	ldi		delayReg2,	0x30
	ldi		delayReg3,	0xFF
	rcall	delay
	rjmp	mainloop


delay:
	dec		delayReg3
	brne	delay
	dec		delayReg2
	brne	delay
	dec		delayReg1
	brne	delay
	ret