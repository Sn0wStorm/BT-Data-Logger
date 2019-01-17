;CKOPT 1, CKSEL3:1	111, CKSEL0 1, SUT1:0	01
.def	var	=	r16
.def	var2 = r17
.def	delayReg1 = r18
.def	delayReg2 = r19
.def	delayReg3 = r20
.def	var3 = r21
.def	char = r22
.def	sensorDataB1 = r23
.def	sensorDataB2 = r24
.def	sensorCRC	= r25

longString: .db "Ein langer, langer Test String.", '\n'

.equ G_LED = 4
.equ R_LED = 5
.equ SCK  = 6
.equ DATA = 7

.equ F_CPU = 4000000                            ; Systemtakt in Hz
.equ BAUD  = 9600                               ; Baudrate

; Berechnungen
.equ UBRR_VAL   = ((F_CPU+BAUD*8)/(BAUD*16)-1)  ; clever runden
.equ BAUD_REAL  = (F_CPU/(16*(UBRR_VAL+1)))      ; Reale Baudrate
.equ BAUD_ERROR = ((BAUD_REAL*1000)/BAUD-1000)  ; Fehler in Promille

.if ((BAUD_ERROR>10) || (BAUD_ERROR<-10))       ; max. +/-10 Promille Fehler
  .error "Systematischer Fehler der Baudrate grösser 1 Prozent und damit zu hoch!"
.endif


init:
	ldi		var,	low(RAMEND) ; init the stack pointer for rcall
	out		spl,	var
	ldi		var,	high(RAMEND)
	out		sph,	var


	; Green LED 4
	; Red	LED 5
	; Sensor SCK 6
	; Sensor Data 7

	ldi		var,	0b11110000
	out		DDRD,	var		;Configure Port D4,5,6,7 as output

	;ldi		var,	0x00
	;out		DDRC,	var		;Configure Ports C as input

	ldi		var,	0b10000000
	out		PORTD,	var		;Enable Pull Up resistor on Port D7

	ldi		var,	0b10010000
	;ldi		var,	0x00
	;ldi		var,	0b00000000
	out		PORTD,	var		; Turn LED on Port D4 on and pull Data high


	; Baudrate einstellen

    ldi     var, HIGH(UBRR_VAL)
    out     UBRRH, var
    ldi     var, LOW(UBRR_VAL)
    out     UBRRL, var

    ; Frame-Format: 8 Bit

    ldi     var, (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
    out     UCSRC, var

    sbi     UCSRB,TXEN                  ; TX aktivieren

	rcall	btTest


	rcall	delay1sec	; wait for the sensor to initialize

	rcall	measureTemp

mainloop:
	;sbic	PIND,	7	; skip next if Input 7 is not active




	rjmp	mainloop

	ldi		zl,		low(longString << 1)	; point the Z Pointer to our constant String in Program Memory
	ldi		zh,		high(longString << 1)
	rcall	btTest

	ldi		var3,	5

	again:
	rcall	blink
	dec		var3
	brne	again

	rjmp	held



measureTemp:
	rcall initSensor
	rcall sendAddr
	rcall sendCmdTemp

	ret


initSensor:

	; Sending the init sequence

	; Set Data to output
	sbi		DDRD,	DATA
	
	; Set Data to 1
	sbi		PORTD,	DATA

	; Set Clock to 1
	sbi		PORTD,	SCK

	; Set Data to 0
	cbi		PORTD,	DATA

	; Set Clock to 0
	cbi		PORTD,	SCK

	; Set Clock to 1
	sbi		PORTD,	SCK

	; Set Data to 1
	sbi		PORTD,	DATA

	; Set Clock to 0
	cbi		PORTD,	SCK

	ret


sendAddr:
	
	; Sending 000

	; Set Data to 0
	cbi		PORTD,	DATA

	ldi		var,	3
	clockAddr:
	; Set Clock to 1
	sbi		PORTD,	SCK
	; Set Clock to 0
	cbi		PORTD,	SCK
	dec		var
	brne	clockAddr
	ret


sendCmdTemp:

	; Sending 000

	ldi		var,	3
	clockTemp1:
	; Set Clock to 1
	sbi		PORTD,	SCK
	; Set Clock to 0
	cbi		PORTD,	SCK
	dec		var
	brne	clockTemp1

	; Sending 1

	; Set Data to 1
	sbi		PORTD,	DATA
	; Set Clock to 1
	sbi		PORTD,	SCK
	; Set Clock to 0
	cbi		PORTD,	SCK
	; Set Data to 0
	cbi		PORTD,	DATA

	; Sending 1, keep Data high

	; Set Data to 1
	sbi		PORTD,	DATA
	; Set Clock to 1
	sbi		PORTD,	SCK


	; Set Clock to 0
	cbi		PORTD,	SCK

	; Set Data to input
	cbi		DDRD,	DATA

	; Wait 3 cycles until reading the Data line
	nop
	nop
	nop

	; If Data is set, skip reading temp
	sbic	PIND,	DATA
	ret

	;			#### Reading Temperature  #### 
	;			#### Send Ack Clock Cycle to acknoledge Sensor response  #### 

	; Turn Red Led on to indicate that we are communicating
	sbi		PORTD,	R_LED

	; Send ACK
	; Set Clock to 1
	sbi		PORTD,	SCK
	; Set Clock to 0
	cbi		PORTD,	SCK

	;			#### Wait for the Sensor to Send Data  #### 

	rcall delay1ms

	waitForTemp:
	; Wait until Data pin is 0
	sbic	PIND,	DATA
	rjmp	waitForTemp


	;			#### Read Data into our registers  #### 


	ldi	sensorDataB1, 0
	ldi	sensorDataB2, 0
	ldi	sensorCRC, 0


	;			#### Read first Byte  #### 

	; Listen for 8 bits
	ldi		var,	8
	ldi		var2,	0b10000000
	clockReadTemp1:
	; Set Clock to 1
	sbi		PORTD,	SCK

	sbic	PIND,	DATA
	or		sensorDataB1, var2

	; Set Clock to 0
	cbi		PORTD,	SCK
	lsr		var2
	dec		var
	brne	clockReadTemp1



	waitForTemp2:
	; Wait until Data pin is 1
	sbis	PIND,	DATA
	rjmp	waitForTemp2

	rcall sendDataAck



	;			#### Read second Byte  #### 


	; Listen for 8 bits
	ldi		var,	8
	ldi		var2,	0b10000000
	clockReadTemp2:
	; Set Clock to 1
	sbi		PORTD,	SCK

	sbic	PIND,	DATA
	or		sensorDataB2, var2

	; Set Clock to 0
	cbi		PORTD,	SCK
	lsr		var2
	dec		var
	brne	clockReadTemp2


	waitForTemp3:
	; Wait until Data pin is 1
	sbis	PIND,	DATA
	rjmp	waitForTemp3

	rcall sendDataAck

	;			#### Read CRC Byte  ####

	; Listen for 8 bits
	ldi		var,	8
	ldi		var2,	0b10000000
	clockReadTemp3:
	; Set Clock to 1
	sbi		PORTD,	SCK

	sbic	PIND,	DATA
	or		sensorCRC, var2

	; Set Clock to 0
	cbi		PORTD,	SCK
	lsr		var2
	dec		var
	brne	clockReadTemp3


	;			#### Reset Outputs to prepare for next transmission  ####

	; Set Data to output
	sbi		DDRD,	DATA

	; Set Data to 1
	sbi		PORTD,	DATA

	; Send ACK
	; Set Clock to 1
	sbi		PORTD,	SCK
	; Set Clock to 0
	cbi		PORTD,	SCK

	; Turn Red Led back of
	cbi		PORTD,	R_LED

	rcall btSendBits
	rcall sendBytes


	ret



sendDataAck:
	; Set Data to output
	sbi		DDRD,	DATA

	; Set Data to 0
	cbi		PORTD,	DATA


	; Send ACK
	; Set Clock to 1
	sbi		PORTD,	SCK
	; Set Clock to 0
	cbi		PORTD,	SCK

	; Set Data to input
	cbi		DDRD,	DATA

	; Enable Data Pull Up Resistor again
	sbi		PORTD,	DATA

	ret



; Send the received bits via bluetooth
btSendBits:

;			#### Send the First Byte  ####

	; Loop for 8 bits
	ldi		var,	8
	mov		var2,	sensorDataB1
	btSendBitsLoop1:
	
	ldi		char,	'1'
	
	; If the left most Bit is set, we skip setting char to '0'
	sbrs	var2,	7
	ldi		char,	'0'

	rcall serout

	; Shift The Sensor data to the left
	lsl		var2
	dec		var
	brne	btSendBitsLoop1

	ldi		char,	' '
	rcall	serout


	;			#### Send the Second Byte  ####

	
	; Loop for 8 bits
	ldi		var,	8
	mov		var2,	sensorDataB2
	btSendBitsLoop2:
	
	ldi		char,	'1'
	
	; If the left most Bit is set, we skip setting char to '0'
	sbrs	var2,	7
	ldi		char,	'0'

	rcall serout

	; Shift The Sensor data to the left
	lsl		var2
	dec		var
	brne	btSendBitsLoop2

	ldi		char,	' '
	rcall	serout


	;			#### Send the CRC Byte  ####

	; Loop for 8 bits
	ldi		var,	8
	mov		var2,	sensorCRC
	btSendBitsLoop3:
	
	ldi		char,	'1'
	
	; If the left most Bit is set, we skip setting char to '0'
	sbrs	var2,	7
	ldi		char,	'0'

	rcall serout

	; Shift The Sensor data to the left
	lsl		var2
	dec		var
	brne	btSendBitsLoop3

	ldi		char,	' '
	rcall	serout

	ldi		char,	'\n'
	rcall	serout


	ret


sendBytes:
	mov char,	sensorDataB1
	rcall serout

	mov char,	sensorDataB2
	rcall serout

	mov char,	sensorCRC
	rcall serout

	ldi		char,	'\n'
	rcall	serout

; Send a Test String via BT
btTest:
    lpm		char,	Z		; Load next Character from Program Memory where Z points to
	or		char,	char	; If loaded 0, set the Zero Status register to 1 
	breq	btTestEnd		; If Zero Status register is set, branch to end

	rcall	serout
	adiw	zh:zl,	1		; Increment the Z Pointer by 1
	rjmp	btTest

	btTestEnd:
    ret

; Put the char into Serial Port
serout:
    sbis    UCSRA,UDRE      ; Wait until usart is ready for the next byte
    rjmp    serout

    out     UDR, char		; Put one character to the usart output
    ret

; Blink the LED
blink:
	;enable led
	sbi		PORTD,	5
	
	;delay for a little while
	rcall	delay1

	;disable led
	cbi		PORTD,	5

	;delay for a long while
	rcall	delay3
	ret


; Wait until the user releases the Button
held:
	sbis	PIND,		7		; skip next if Input 7 is active
	rjmp	held
	ldi		delayReg1,	0x01
	ldi		delayReg2,	0x30
	ldi		delayReg3,	0xFF
	rcall	exeDelay
	rjmp	mainloop


; 1ms Delay

delay1ms:
	ldi		delayReg1,	1
	ldi		delayReg2,	6
	ldi		delayReg3,	49
	rcall exeDelay
	ret

; A Shorter Delay
delay1:
	ldi		delayReg1,	1
	ldi		delayReg2,	0
	ldi		delayReg3,	0
	rcall exeDelay
	ret

; A little longer Delay
delay3:
	ldi		delayReg1,	3
	ldi		delayReg2,	0
	ldi		delayReg3,	0
	rcall exeDelay
	ret

; Delay for 1 second
delay1sec:
	ldi  delayReg1, 21
    ldi  delayReg2, 75
    ldi  delayReg3, 191
	rcall exeDelay
	ret

; Execute the Delay
exeDelay:
	dec		delayReg3
	brne	exeDelay
	dec		delayReg2
	brne	exeDelay
	dec		delayReg1
	brne	exeDelay
	ret
