; ### WORK IN PROGRESS !! ###
;  Some code borrowed from: http://www.muppetlabs.com/~breadbox/software/tiny/snake.asm.txt
;
;  Name		   : ASCII Space Invaders
;  Version         : 1.0
;  Creation date   : Oct 7th, 2015
;  Last update     : Nov 10th, 2015
;  Author          : brennanhm
;  Description     : The Martians are invading and we need YOU to save planet Earth!
;		     Program designed to run in Linux on a 32bit x86 processor
;
;  Build using these commands:
;    nasm -f elf -g -F dwarf spaceinv.asm
;    ld -m elf_i386 -o spaceinv spaceinv.o
;
;

; CHANGELOG:
; Oct 19th, 2015 - The game no longer uses VT-100 special line chars. The screen is filled with standard ASCII.
; Oct 24th, 2015 - Added alien spacecraft & a timer control (ALIENSPEED1) to pace their attack.
;		   Laser detects collisions with aliens and causes them to disappear
; Oct 26th, 2015 - Score increases when alien is destroyed. Current MAX SCORE is 99.
;		   Game exits if alien reaches bottom row
; Oct 27th, 2015 - Game exits when alien and spaceship collide. Moved refresh call below code that copies scr buffer to outbuf.
;		 - Removed unnecessary code
;		 - Added alienswin exit routine to display message when player fails
;		 - Added playerwins exit routine to display congratulations message
;		 - Changed SIG Alarm timer to (25 * 1000) from (50 * 1000) to increase speed of gameplay
; Oct 29th, 2015 - Increased # of aliens from one to three
; Nov 2nd, 2015	 - Changed aliencounter variable to resd from resb to prevent crashes in the moveAlien routine. Used gdb to determine ECX counter sometimes reached 65000+ causing segmentation fault.
;		 - Score determines number of aliens on screen. Currently using LEVEL1, LEVEL2, and LEVEL3 constants to test score value.
;		 - Added flash effect when aliens are hit by laser
; Nov 3rd, 2015  - Modified lasercheck routine so that laser hits are not registered when alien is disintegrating (flashing)
;		 - Modified alienmove routine so that aliens don't advance forward if they're flashing
;		 - Edited alienmove routine to create aliens to do not overlap
; Nov 5th, 2015	 - Game ends (aliens win) when alien collides with spaceship
; Nov 6th, 2015  - Ship stalls and flashes when hit by an alien. Alien movement is also halted.
; Nov 10th, 2015 - Incorporated intro, which contains instructions, into the main program. 
; Nov 11th, 2015 - Added "angry alien" art. The angry aliens move faster than the normal ones and are worth two points when destroyed.
; 		 - Two constants represent alien speed. ALIENSPEED1 = normal speed. ALIENSPEED2 = angry alien speed. If the fastalien variable flag is raised, the alien move routine uses ALIENSPEED2.
;		 - Mixed up the levels so there is a mixture of normal and angry aliens in various numbers. Currently, player must score 100 points to win.

; TODO

; Energy packs + Energy usage tracking
; Continuos movement to left and right with one key press
; Optimize code
; Improve code documentation
; Move the second collision check into move alien routine?
; Check lasercheck shipflash code (will continue incrementing after collision)
; Add points

; CURRENT BUGS
; Lower half of screen flashes when terminal height and width increased
; 'Any key' does not include ctrl, shift, or alt

; FIXED BUGS
;
; Problem: Sometimes laser goes through alien.
; Cause: Need to check for collision before and after alien moves
; Problem: Alien destroyed when landing above score
; Cause: Alien only checking for non-space before moving. Specifically check for laser now.
;
; Nov 10th, 2015
; Problem: Aliens sometimes land unevently during exit
; Cause: Loop exits before all aliens advance. 
; Solution: Set an alienwin flag instead and check if after loop.

;#########################################################################
;# Macros / Constants							##
;#########################################################################

; Linux system calls used by this program
; http://syscalls.kernelgrok.com/ for details

%define	SC_read		3				; EAX = read(ebx, ecx, edx)
%define SC_write	4				; EAX = write(ebx, ecx, edx)
%define SC_pause	29				; EAX = pause()
%define SC_ioctl	54				; EAX = ioctl(ebc, ecx, edx)
%define SC_sigaction	67				; EAX = sigaction(ebx, ecx, edx)
%define	SC_gettimeofday 78				; EAX = gettimeofday(ebx, ecx)
%define SC_setitimer	104				; EAX = setitimer(ebx, ecx, edx)
%define SC_select	142				; EAX = select(ebx, ecx, edx, esi, edi)

; ioctl ( input/output control) values

%define TCGETS		0x5401				; Get console settings
%define TCSETS		0x5402				; Set console settings
%define ICANON		0000002				; Canonical mode
%define ECHO		0000010				; Echo mode

; Linux signal values

%define SIGALRM		14

; ASCII character codes for terminal manipulation ('q' = NASM octal notation)
%define SI		017q				; Shift In
%define ESC		033q				; Escape
%define SO		016q				; Shift Out

; Game constants

%define INTROSPEED	60				; Speed at which stars move in intro screen (lower is faster)
%define GAMESPEED	25				; Speed setting for main game (lower is faster)
%define NULL		0				; Define NULL as zero
%define NONZERO		1				; Define NONZERO as one
%define MAXSCORE	100				; Game exits with success message when this score is reached
%define LEVEL1		4				; Scores required to reach each level
%define LEVEL2		8
%define LEVEL3		12
%define LEVEL4		24
%define LEVEL5		32
%define LEVEL6		44
%define LEVEL7		56
%define LEVEL8		72
%define LEVEL9		84
%define LEVEL10		100
; Dimensions of the screen and playing area
; Adjust these to play on a larger terminal (ex: 132 x 43)
%define TERMWIDTH	80				; Console terminal width = 80. 
%define HEIGHT		24				; Console terminal height = 24.
%define BOTTOMROW	'24'				; Used for terminal manipulation
; Starting Coordinates
%define	TOPROW		1				; From what row the intro message will start
%define CENTERROW	HEIGHT / 2			; Calculate center row to display messages to user
%define SHIPSTART	(TERMWIDTH * (HEIGHT - (SHIPHEIGHT + 1) ) ) + (TERMWIDTH / 2)	; Ship starting point. +1 for status bar
%define SHIPMAXRIGHT	SHIPSTART + (TERMWIDTH / 2) - 5	; Define max left and right to prevent ship from going out of bounds
%define SHIPMAXLEFT	SHIPSTART - (TERMWIDTH / 2) + 3	; 

; (Intro) Star Constants
%define FORMSPEED	10				; Controls speed at which new stars are formed
%define MAXSTARS	10				; Maximum number of stars allowed on the screen at one time

; Ship Constants
%define SHIPHEIGHT	5				; Ship's height, in rows
%define SHIPWIDTH	8				; Ship's width, in columns

; Alien Constants
%define MAXALIENS	10				; The maximum number of aliens on the screen at any one time
%define	ALIENSPEED1	18				; Normal alien speed
%define ALIENSPEED2	11;18				; Angry alien speed
							; Compared against alienspdctl to see if alien should move. Lower is faster, higher is slower. Note: 0 won't work.
%define ALIENHEIGHT	3				; Heigh (in rows) of the alien
%define ALIENWIDTH	7				; Width (in columns) of the alien
							; Prevents alien from getting cut off on the right side
%define	ALIENPADDING	1				; Padding to be added to starting position
							; Prevents characters in second line from being cut off 
%define UNDERALIEN	(ALIENHEIGHT * TERMWIDTH) - ALIENPADDING	; Used to calculate the first element of space below alien
%define AFLASHLENGTH	25				; How long aliens flash after being hit (higher is longer)

;#########################################################################
;# Initialized Data							##
;#########################################################################

section .data

; Intro Messages and their lenghts
intromsg: 		db "ASCII Space Invaders V1.0"
INTROMSGLEN: 		equ $-intromsg			
intromsg2:		db "Instructions:"
INTROMSG2LEN:		equ $-intromsg2
intromsg3:		db "- Move spaceship using arrow keys"
INTROMSG3LEN:		equ $-intromsg3
intromsg4:		db "- Hit spacebar to fire laser"
INTROMSG4LEN:		equ $-intromsg4
intromsg5:		db "- Press 'q' to exit at any time"
INTROMSG5LEN:		equ $-intromsg5
intromsg6:		db "- Score 100 points to save Earth" 
INTROMSG6LEN:		equ $-intromsg6
intromsg7:		db "Press any key to start!" 
INTROMSG7LEN:		equ $-intromsg7

; Scoreboard message
scoreboard		db "Score = "			; Scoreboard
SCOREBOARDLEN:		equ $-scoreboard		; Length
; Game Characters
space:			db " "				; What is space?
laserchar:		db "|"				; Laser character
starchar:		db "|"				; Star character

; Ending Messages
alienswin1:		db "Aliens Win"			; Failure message #1
ALIENSWIN1LEN:		equ $-alienswin1		; Length
playerwins1:		db "Humans Win"			; Win message #1
PLAYERWINS1LEN:		equ $-playerwins1		; Length
playerwins2:		db "Congratulations. You saved Earth!" ; Win message #2
PLAYERWINS2LEN:		equ $-playerwins2		; Length

; This table gives us pairs of ASCII digits from 0-99. 
; Scalable to 999
digits:			db "000001002003004005006007008009010011012013014015016017018019"
			db "020021022023024025026027028029030031032033034035036037038039"
			db "040041042043044045046047048049050051052053054055056057058059"
			db "060061062063064065066067068069070071072073074075076077078079"
			db "080081082083084085086087088089090091092093094095096097098099"
			db "100101102103104105106107108109110111112113114115116117118119"
DIGITSLEN:		equ 3				; Length of digits

; Spaceship strings
; http://ascii.gallery/art/tag/spaceship

; sjw  /\
;     (  )
;     (  )
;    /|/\|\
;   /_||||_\

spcshp1:		db	"/\"
SPCSHP1LEN:		equ $-spcshp1
spcshp2:		db     "(  )"
SPCSHP2LEN:		equ $-spcshp2
spcshp3:		db     "(  )"
SPCSHP3LEN:		equ $-spcshp3
spcshp4:		db    "/|/\|\"
SPCSHP4LEN:		equ $-spcshp4
spcshp5:		db   "/_||||_\"
SPCSHP5LEN:		equ $-spcshp5

; Alien strings
; http://www.retrojunkie.com/asciiart/celest/aliens.htm
;
; Calm alien
;
;    _/_\_     
;   (o_o_o)  
;    / | \
;
; Angry alien
;
;     \ /
;   ((o.o))
;    //^\\
	
alien1:			db	"_/_\_"
ALIEN1LEN:		equ $-alien1
alien2:			db     "(o_o_o)" 
ALIEN2LEN:		equ $-alien2
alien3:			db      "/ | \"
ALIEN3LEN:		equ $-alien3

alien4:			db	" \ / "
ALIEN4LEN:		equ $-alien4
alien5:			db     "((o.o))"
ALIEN5LEN:		equ $-alien5
alien6:			db	"//^\\"
ALIEN6LEN:		equ $-alien6

; The structure passed to the sigaction system call.
sigact:		dd	tick				; 'tick' label is located in the refresh procedure

;#########################################################################
;# Unitialized Data							##
;#########################################################################

section .bss

		resd 3					; Remainder of sigact structure (see above). Unnecessary?

; The player's current score
score: 		resd 1

; Current seed value for the pseudorandom number generator
rndseed:	resd 2

; Keyboard input queue
key:		resb 4

; TTY attributes stored here
termios: 	resd 3
.lflag:		resd 1
		resb 44
		
; Used to set a system alarm. Serves as a timeval structure and an itimerval structure
timer:		resd 4

; The screen array. All screen elements including spaceship, aliens, laser, score, etc are drawn in this buffer
scr:		resb TERMWIDTH * HEIGHT

; Buffer to store program's output, which is written to standard output
; 8192 allows for larger terminal windows (ex: 132 x 43 )
outbuf:		resb 8192;4096

; Ship coordinates
ship:		resd 1

; Flag set when ship hit by alien
shipflash:	resd 1

; Amount of time ship will flash before game ends
shipflashtimer:	resd 1

; Laser coordinates
laser:		resd 1

; Alien coordinate table
alien:		resd MAXALIENS

; Alien flash table. Tracks which aliens are flashing
alienflash:	resd MAXALIENS

; Alien flash timer table. Each alien has its own flash timer
alienflashtimer: resd MAXALIENS

; Alien speed flag. If set to a non-zero value, alien moves fast
fastalien:	resd 1

; Used to control when aliens advance forward
alienspdctl:	resb 1

; Alien invaders. Keeps track of how many aliens are on screen
invaders:	resd 1

; Alien loop control
; Used to process the correct number of elements in the alien table.
aliencounter:	resd 1

; Flag set to non-zero value if aliens win
alienwin:	resd 1

; Star coordinate table
star:		resd MAXSTARS

; Used to control the speed at which new stars are formed
starspdctl:	resd 1

; Used to count through the star table elements
starcounter:	resd 1

; The file description bit array used by the select system call
fdset:		resd 32

section .text							; Section containing code

;#########################################################################
;# Functions / Routines / Procedures					##
;#########################################################################

; GetKey()
;
; Description: getkey retrieves a single character from standard input if one is waiting to be read.
;
; Input: 
; ECX = pointer to a byte in memory at which to store the character.
;
; Output:
; AL = the contents of [ECX].
; [ECX] = the character input, or zero if no character was available, or 'q' if standard input could not be read.
;
; EAX, EBX, and EDX are altered.

getkey:

; Call select(), waiting on the first file descriptor only, and setting
; the time to wait to zero. If select returns an error, return 'q' to
; the caller. If select returns zero, return zero to the caller.
; Otherwise, call read.
; select() is called before read() to prevent the program from blocking while waiting for user input.

		xor	eax, eax				; Zero the EAX register
		xor	ebx, ebx				; Zero the EBX register
		;Parm #3 EDX (NULL): writefds will be watched to see if space is available for write (NULL is this case)
		cdq						; Convert double to quad. EAX becomes EDX:EAX (Zero EDX register)
		mov 	[ecx], al				; Copy zero (register was zero'd above) to where ECX points (key). It will remain zero if no key was pressed.
		pusha						; Push all 16 bit registers onto the stack for safekeeping
		;Parm #1 EBX (1): nfds is the highest-numbered file descriptor in any of the three sets, plus 1. stdin (0) + 1 = 1
		inc	ebx					; Increment EBX (to 1) in preparation for select call	
		;Parm #2 ECX (fdset): readfds will be watched to see if characters become available for reading (more precisely, to see if a read will not block; in particular, a file descriptor is also ready on end-of-file)
		mov	ecx, fdset				; Copy address of fdset (file description bit array) into ECX
		mov	[ecx], ebx				; Copy EBX value (1) into fdset
		;Parm #4 ESI (NULL): exceptfds will be watched for exceptions (NULL in this case)
		xor	esi, esi				; Zero ESI register
		;Parm #5 EDI (timer): The timeout argument specifies the interval that select() should block waiting for a file descriptor to become ready.
		mov	edi, timer				; Copy the address of timer into EDI
		; If both fields of the timeval structure are zero, then select() returns immediately.  (This is useful for polling.)
		mov	[edi], eax				; Copy EAX (4 bytes of zero) into timer (set seconds to zero)
		mov	[byte edi + 4], eax			; Copy EAX (4 bytes of zero) starting at timer's fourth byte (set microseconds to zero)
		mov	al, SC_select				; Copy 142 (select() system call number) into the low byte of EAX
		int	0x80					; Perform system call, which checks stdin without blocking. EAX will be 1 if there was a character waiting, 0 if nothing was there, or -1 if there was an error.
		dec	eax					; Decrement EAX (affects overflow and sign flags) 
		popa						; Restore all 16 bit registers from the stack (Even though EAX is restored, the flags remain set from the int instruction)
		; Jump if less (overflow AND sign flags raised)
		jl	.return					; 0 was returned (nothing there). The overflow flag is set when an operation would cause a sign change. 0 - 1 = -1 (raises overflow & sign flags)
		; Jump if sign flag raised
		js	.retquit				; Error code returned (-1). Quit game. -1 - 1 = -2 (would not set the overflow flag)
		mov	al, SC_read				; There is a character waiting to be read (1 - 1 = 0), so call read(). Copy SC_read system call value into AL
		inc	edx					; Increment EDX to 1 (byte count to read)
		int	0x80					; Perform system call.
								; EBX (file descriptor) returned to 0 (stdin) after the popa instruction
								; ECX (buffer) is pointing to key, where the key will be copied
								; EDX (count) is at one.
								
; If read returned zero (i.e., EOF) or an error, return 'q' to the
; caller. Otherwise, return the retrieved character.

		dec	eax					; Decrement EAX (EAX should be 1 for success, because one byte was read)
		jz	.return					; If zero (one byte was read), jump to return
.retquit:	mov	byte [ecx], 'q'				; Error was returned (or EOF), so place 'q' in key to quit game
.return:	mov	al, [ecx]				; Return the key that was pressed (Or zero if no key was pressed)
		ret						; Return
		
; LaserCheck()
;
; Description: This routine checks to see if an alien has been hit by a laser
;
; Input: N/A
;
; Output: N/A
;
; Altered: EAX, ECX, EDI		
; Check if any of the aliens have been hit by a laser

lasercheck:	
		mov	ecx, [aliencounter]			; Used to process the correct number of elements in the alien table. 
.startloop:	mov	ebx, alien				; Copy address of alien table into EBX
		dec	ecx					; 
		lea	edx, [ebx+ecx*4]			; Get the memory address of the current alien							
								; ( alien + counter * 4)
		inc	ecx
		; First check if the alien still exists
		cmp	[edx], dword NULL			; Check the value within. If zero, the alien has been destroyed.
		jz	.doloop1				; Skip if zero. ie: jump to .doloop to decrement counter and restart
		; Next, check if it's just been hit (flashing)
		mov	ebx, alienflash				; Copy the address of the alienflash table into EBX
		dec	ecx
		lea	ebp, [ebx+ecx*4]			; Get the memory address of the flash slot for the alien being processed
		inc	ecx
		cmp	[ebp], DWORD NULL			; Compare it to zero
		jnz	.doloop1				; If NOT zero that means the alien is flashing, so DO NOT check for laser hit
		; We can proceed with checking for a laser hit now
		mov	edi, scr				; Copy location of scr buffer into EDI
		add	edi, [edx]				; Add distance to alien
		add	edi, UNDERALIEN				; Add distance to the first chunk of space just below alien
; Only space below alien?
		mov	eax, ALIENWIDTH				; Copy alien width into EAX (the counter)
.checkspace:	mov	bl, [edi]				; Copy the first space block into BL
		cmp	bl, [space]				; Is it just space?
		jnz	.hit					; Not space? Check if alien was hit by laser or collided with spaceship
		inc	edi					; Increment EDI to next space block
		dec	eax					; Decrement the counter
		jnz	.checkspace				; Loop back and check next space block
.doloop1	loop	.startloop				; Check below all other aliens
		ret						; Only space, return to caller
; Is it a laser?
.hit:		cmp	bl, [laserchar]				; Was it hit by a laser?
		jnz	.shiphit				; No? Then it collided with spaceship. Set ship flash flag.
								; Otherwise, process destroy alien instructions
		mov	dword [laser], NULL			; Erase laser
		cmp	[fastalien], dword NULL			; Is it a fast alien?
		jz	.onepoint				; If not, only one point
		inc	dword [score]				; Fast aliens are worth two points
.onepoint	inc	dword [score]				; Increment the score
		; Set the alien flash flag
		mov	edx, alienflash				
		dec	ecx
		lea	ebx, [edx+ecx*4]
		inc	ecx
		inc	dword [ebx]				; Set flag to non-zero value			
		
		mov	eax, [score]				; Copy value of score into EAX
		cmp	eax, MAXSCORE				; Compare it to MAXSCORE
		jge	playerwins				; Jump to playerwins instructions if max score has been reached
		jmp	.return					; Otherwise, return to caller
.shiphit	inc	dword [shipflash]			; Set the shipflash flag
.return		ret						; Return to caller

		
; FlashAlien()		
; Description: This routine checks if the alien should flash.
; If the alien's flash flag is set, the drawalien routine will be called once every two loop interations, causing a flash effect.
;
; Input: 
;
; Output:
;
; Altered:
flashalien:
		mov	ecx, [aliencounter]			; Set ECX counter to number of aliens to process
.flashloop:	mov	ebx, alien				; Copy address of alien table into EBX	
		dec	ecx					; Decrement counter (for memory calculation)
		lea	edx, [ebx+ecx*4]			; Add ( (counter - 1) * 4) to EBX to the current alien's effective memory address
								; EDX will hold the address of the alien for the rest of the iteration of the loop
		inc	ecx					; Restore counter
		cmp	[edx], dword NULL			; No Alien?	
		jz	.doloop					; Then proceed to next element in array
		mov	ebx, alienflash				; Copy address of alienflash table into EBX
		dec	ecx
		lea	ebp, [ebx+ecx*4]			; Get address of the alien's flash flag
		inc	ecx
		cmp	[ebp], dword NULL			; Is it zero?
		jz	.draw					; If so, draw the alien normally
								; Otherwise, alien should flash
		mov	ebx, alienflashtimer			; Copy address of alienflashtimer table into EBX
		dec	ecx
		lea	eax, [ebx+ecx*4]			; Get address of alien's flash timer
		inc	ecx
		cmp	[eax], dword AFLASHLENGTH		; Compare it to alien flash length 
		jge	.endflashing				; If greater or equal, jump to .end flashing to reset timer and delete alien
								; Otherwise, check if it's time to flash
		xor	ebx, ebx				; Zero EBX register
		add	ebx, [eax]				; Add timer to ebx
		jp	.flashdraw				; If parity flag set, draw alien
		jmp	.noflash				; Otherwise, don't draw (flash effect)
		
.flashdraw	call	drawaliens
		inc	dword [eax]				; Increment the flash timer
		jmp	.doloop
.noflash	inc	dword [eax]
		jmp	.doloop
.endflashing	mov	[eax], dword NULL			; Flashing complete. Reset alien's flash timer
		mov	[ebp], dword NULL			; Set alien's flash flag to zero
		mov	[edx], dword NULL			; Zero alien.
		dec	dword [invaders]			; Decrement number of invaders
		jmp	.doloop					; Process remaining aliens
.draw		call	drawaliens				; ECX holds index into alien table
.doloop		loop	.flashloop	
		ret						; Return to caller
		
; FlashShip()
; Description: This routine checks if the ship should flash.
; If the shipflash variable is set to a non-zero value, the ship will be drawn once per two loop iterations
;
; Input: 
;
; Output:
;
; Altered:
flashship:
		mov	ebx, shipflash				; Copy address of the shipflash flag variable into EBX
		cmp	[ebx], dword NULL			; Is it zero?
		jz	.draw					; If so, draw the alien normally
								; Otherwise, alien should flash
								
		mov	ebx, shipflashtimer			; Copy address of alienflashtimer table into EBX
		cmp	[ebx], dword 100			; Compare it to 25 (create constant SHIPFLASHTIMER)
		jge	.endflashing				; If greater or equal, jump to .endflashing and end the game (aliens win)
								; Otherwise, check if it's time to flash
		xor	eax, eax				; Zero EAX register
		add	eax, [ebx]				; Add timer to ebx
		jp	.flashdraw				; If parity flag set, draw alien
		jmp	.noflash				; Otherwise, don't draw (flash effect)
		
.flashdraw	call	drawship
		inc	dword [ebx]				; Increment the flash timer
		jmp	.finish
.noflash	inc	dword [ebx]
		jmp	.finish
.endflashing	mov	[ebx], dword NULL			; Flashing complete. Reset alien's flash timer
		jmp	alienswin				; Process remaining aliens

.draw		call	drawship				; ECX holds index into alien table
.finish		ret		
		
; EraseScr()
; Description: Erase screen buffer in preparation for a new frame
;
; Input: N/A
;
; Output: N/A
;
; Altered: EAX, ECX, EDI

erasescr:

		push eax					; Save registers
		push ecx
		push edi
		
		mov	edi, scr				; Load the address of the scr array into EDI
		mov	al, [space]				; Copy space into AL
		push	TERMWIDTH * HEIGHT			; Push TERMWIDTH * HEIGHT onto the stack
		pop	ecx					; Pop it into counter register ECX
		rep stosb					; Blast space into the buffer
		
		pop edi						; Restore registers
		pop ecx
		pop eax
		ret						; Return to caller
		
; Refresh()
; Description: Writes the contents of the outbuf buffer to standard output.
;
; Input:N/A
;
; Output:N/A
; 
; EAX, EBX, ECX, and EDX are altered.

refresh:
; The terminal screen is erased, The scr array is read, and each element is output, with a newline
; inserted at the end of each row.
; http://umich.edu/~archive/apple2/misc/programmers/vt100.codes.txt

		pushad
		mov	edi, outbuf				; Copy location of outbuf into EDI

		mov	eax, ESC | ('[H' << 8) | (ESC << 24)	; <ESC>[H escape code sets the cursor to the home position (first column of first row)
		stosd						; Copy the value in EAX to [EDI], which points to outbuf. EDI is then incremented
		mov	eax, '[J' | (SO << 16) | (SO << 24)	; Move the value "Shift Out Shift Out [J" into EAX. '[J' escape code clears screen.
		stosd						; Copy the value in EAX to [EDI]
		mov	esi, scr				; Copy the address of scr into ESI (source buffer)
		push	byte HEIGHT				; Push byte's worth of HEIGHT value onto the stack
		pop	ecx					; Pop it immediately into ECX (will only fill low byte CL)
.initoutloop:	mov	ch, TERMWIDTH				; Move the value of TERMWIDTH into the high byte of ECX
.lineoutloop:	lodsb						; Load byte at address ESI into AL.
		stosb						; Copy the byte in AL to EDI (outbuf). EDI is then incremented.
		dec	ch					; Decrement the high byte (TERMWIDTH) in CX
		jnz	.lineoutloop				; If not zero, continue writing the line
		dec	ecx					; When TERMWIDTH reaches zero, decrement the HEIGHT (line done)
		jz	.outloopend				; If ECX is zero, jump to the end of the loop
		mov	al, 10					; If not, move the value 10 (End of line) into AL
		stosb						; Copy it into EDI (outbuf) to complete the line
		jmp	short .initoutloop			; Jump to process next line in buffer
.outloopend:	nop

		mov	eax, ESC | ('[' << 8) | (BOTTOMROW << 16)	; BOTTOMROW = 24. Move 'ESC [ 24' into EAX (underline off)
		stosd							; Store EAX (all four bytes) to [EDI]. Increment EDI by four
		mov	eax, ';0H' | (SI << 24)				; Move cursor to home position?
		stosd							; Copy EAX to [EDI]
		mov	edx, edi					; Copy EDI to EDX (EDX becomes one past the last character in outbuf to write)
		mov	edi, outbuf					; Copy address of outbuf into EDI
		mov	ecx, edi					; Copy EDI to ECX (ECX = the buffer to write to stdout)
		sub	edx, ecx					; Subtract ECX from EDX (EDX = count of bytes to be written)
		xor	ebx, ebx					; Zero the EBX register
		mov	eax, SC_write
		inc	ebx						; Increment EBX to 1 (EBX = fd = 1 = stdout)
		int	0x80						; Perform system call
		
		popad							; Restore all registers
tick:		ret							; Return (also part of signal timer struct)

	
; DrawStars()
; Description: Draws the stars for the intro
;
; Input:
;
; Output:
;
; Altered
drawstars:
		pushad						; Save all regisers
		mov	ecx, MAXSTARS				; Copy MAXSTARS value into ECX. To be used as counter
		mov ebx, star					; Copy star table address into EBX
		
.starloop	xor 	edx, edx				; Zero EDX regiser
		dec ecx
		lea edx, [ebx+ecx*4]				; Get address of star
		inc ecx
		cmp	[edx], dword NULL			; Is it zero?
		jz	.doloop					; If so, decrement ECX and check next element
								; Otherwise...
		mov edi, scr					; Point EDI to scr buffer
		add edi, [edx]					; Add star's coordinates to EDI
		mov al, [starchar]				; Copy star character into AL
		stosb						; And then copy it into the screen buffer at the correct coordinates
		
.doloop		loop	.starloop				; Decrement ECX and check next element
		
		popad						; Restore all registers
		ret						; Return to caller
		
; DrawIntroMsg()
; Description: Prints the intro messages (name, version #, instructions, etc) to the screen 
;
; Input:
;
; Output:
;
; Altered:
drawintromsg:
		pushad						; Save all registers
		
		xor	edx,edx
		mov 	esi, intromsg				; Copy message address into ESI
		mov 	ecx, INTROMSGLEN			; Copy length into ECX
		mov 	edx, TOPROW				; Copy center row into EDX (height / 2)
		call 	wrtcntr					; Call the write center routine
		mov 	esi, intromsg2				; Copy 2nd message address into ESI
		mov 	ecx, INTROMSG2LEN			; Copy lenght to ECX
		mov 	edx, TOPROW + 2				; Copy to center row + 1
		call	wrtcntr					; Call the write center routine
		mov 	esi, intromsg3				; Copy 2nd message address into ESI
		mov 	ecx, INTROMSG3LEN			; Copy lenght to ECX
		mov 	edx, TOPROW + 4				; Copy to center row + 1
		call	wrtcntr					; Call the write center routine
		mov 	esi, intromsg4				; Copy 2nd message address into ESI
		mov 	ecx, INTROMSG4LEN			; Copy lenght to ECX
		mov 	edx, TOPROW + 5				; Copy to center row + 1
		call	wrtcntr					; Call the write center routine
		mov 	esi, intromsg5				; Copy 2nd message address into ESI
		mov 	ecx, INTROMSG5LEN			; Copy lenght to ECX
		mov 	edx, TOPROW + 6				; Copy to center row + 1
		call	wrtcntr					; Call the write center routine
		mov 	esi, intromsg6				; Copy 2nd message address into ESI
		mov 	ecx, INTROMSG6LEN			; Copy lenght to ECX
		mov 	edx, TOPROW + 7				; Copy to center row + 1
		call	wrtcntr					; Call the write center routine
		mov 	esi, intromsg7				; Copy 2nd message address into ESI
		mov 	ecx, INTROMSG7LEN			; Copy lenght to ECX
		mov 	edx, TOPROW + 9				; Copy to center row + 1
		call	wrtcntr					; Call the write center routine
		
		popad						; Restore all registers
		ret						; Return to caller
	
; DrawShip()
; Description: Draw the spaceship to scr buffer starting at its current coordinates
;
; Input: 
;
; Output:
;
; Altered:

drawship:

		push eax					; Save modified registers
		push ebx					
		push ecx
		push esi
		push edi
		
		
		mov ebx, [ship]					; Copy ship's coordinates into EBX
		mov edi, scr					; Point EDI to scr buffer
		add edi, ebx					; Add Spaceship start coordinate
		mov esi, spcshp1				; Spaceship line 1
		mov ecx, SPCSHP1LEN				; Length
		;cld
		rep movsb					; Copy line 1
				
		mov edi, scr + (TERMWIDTH - 1)			; Point EDI to scr buffer + Character positioning
		add edi, ebx 					; Add spaceship start coordinate
		mov esi, spcshp2
		mov ecx, SPCSHP2LEN
		rep movsb
		
		mov edi, scr + (TERMWIDTH * 2 - 1)
		add edi, ebx 
		mov esi, spcshp3
		mov ecx, SPCSHP3LEN
		rep movsb
		
		mov edi, scr + (TERMWIDTH * 3 - 2)
		add edi, ebx
		mov esi, spcshp4
		mov ecx, SPCSHP4LEN
		rep movsb
		
		mov edi, scr + (TERMWIDTH * 4 - 3)
		add edi, ebx
		mov esi, spcshp5
		mov ecx, SPCSHP5LEN
		rep movsb
		
		pop edi						; Restore registers
		pop esi
		pop ecx
		pop ebx	
		pop eax
		ret						; Return to caller
		
; DrawAliens()
; Description: This function is called by FlashAlien() and will draw an alien at its coordinates
;
; Input:
; ECX - index of alien in alien table
;
; Output:
;
; Altered:

drawaliens:
		push 	eax					; Save modified registers
		push	ebx
		push	ecx
		push	edx
		push	esi
		push	edi
		
		xor 	edx, edx				; Zero EDX regiser
		mov ebx, alien					; Copy alien's address into EAX
		dec ecx
		lea edx, [ebx+ecx*4]				; Get address of alien 
		inc ecx
		
		cmp	[fastalien], byte NULL			; Angry alien flag set?
		jnz	.angryalien				; If so, draw an angry alien
		
		mov edi, scr					; Point EDI to scr buffer
		add edi, [edx]					; Add alien's coordinates to EDI
		mov esi, alien1					; Alien line 1
		mov ecx, ALIEN1LEN				; Length
		rep movsb					; Copy line 1
				
		mov edi, scr + (TERMWIDTH - 1)			; Point EDI to scr buffer + Character positioning
		add edi, [edx] 					; Add alien's coordinates to EDI
		mov esi, alien2					; Alien line 2
		mov ecx, ALIEN2LEN				; Length
		rep movsb					; Copy line 2
		
		mov edi, scr + (TERMWIDTH * 2)			; Point EDI to scr buffer + 3rd row
		add edi, [edx] 					; Add alien's coordinates to EDI
		mov esi, alien3					; Alien line 3
		mov ecx, ALIEN3LEN				; Length
		rep movsb					; Copy line 3
		
		jmp	.finish
		
.angryalien:

		mov edi, scr					; Point EDI to scr buffer
		add edi, [edx]					; Add alien's coordinates to EDI
		mov esi, alien4					; Alien line 1
		mov ecx, ALIEN1LEN				; Length
		rep movsb					; Copy line 1
				
		mov edi, scr + (TERMWIDTH - 1)			; Point EDI to scr buffer + Character positioning
		add edi, [edx] 					; Add alien's coordinates to EDI
		mov esi, alien5					; Alien line 2
		mov ecx, ALIEN2LEN				; Length
		rep movsb					; Copy line 2
		
		mov edi, scr + (TERMWIDTH * 2)			; Point EDI to scr buffer + 3rd row
		add edi, [edx] 					; Add alien's coordinates to EDI
		mov esi, alien6					; Alien line 3
		mov ecx, ALIEN3LEN				; Length
		rep movsb					; Copy line 3
		
		
.finish:
		pop edi						; Restore registers
		pop esi
		pop edx
		pop ecx
		pop ebx	
		pop eax
		ret						; Return to caller

	
; DrawLaser()
; Description: Draw laser to screen buffer at its current coordinates
;
; Input: 
;
; Output:
;
; Altered

drawlaser:
		push 	eax					; Save modified registers
		push	edx
		push	edi
		
		xor 	edx, edx				; Zero EDX regiser
		add	edx, [laser]				; Add laser coordinates
		jz	.nolaser				; Zero? That means no laser exists
		mov	edi, scr				; Otherwise, set EDI to point to scr buffer
		add	edi, [laser]				; Add laser's position to EDI
		mov	al, [laserchar]				; Copy laser character into AL
		stosb						; And then copy it to the buffer
.nolaser:
		pop edi						; Restore registers
		pop edx
		pop eax
		ret						; Return to caller
		
; DrawScore()
; Description: Draw score at the bottom right corner of the screen
;
; Input:
; ESI = location of source string
; ECX = length of string
; EDX = row number
;
; Output:
;
; Altered:

drawscore:

		push eax					; Save modified registers
		push ecx
		push edx
		push edi
		push esi
		push ebp
		
		mov	ecx, SCOREBOARDLEN + DIGITSLEN		; Copy length of scoreboard + digits into ECX
		mov	eax, TERMWIDTH				; Copy screen TERMWIDTH value into EAX
		mov	edx, (HEIGHT - 1)			; Copy bottom row into EDX
		mul	edx					; Multiply it by the width. Result goes into EAX
		mov	edi, scr				; Set EDI to point to scr buffer
		add	edi, eax				; Position EDI to the beginning of the bottom row
		mov	eax, TERMWIDTH				; Copy TERMWIDTH back into EAX, which was overwritten by MUL instruction
		sub	eax, ecx				; Subract length of scoreboard + digits from TERMWIDTH
		add 	edi, eax				; Add the correct number of spaces to EDI so that score is right aligned
		cld						; Clear directional flag to ensure EDI is increased
		mov	esi, scoreboard				; Move location of scoreboard into ESI
		mov	ecx, SCOREBOARDLEN			; Copy scoreboard length into ECX (counter)
		rep	movsb					; Copy scoreboard into scr buffer
		mov	ebp, [score]				; Copy score value into EBP
		lea 	esi, [digits+ebp*DIGITSLEN]		; Load location of correct digits (digits + score * DIGITSLEN) into ESI
		mov	ecx, DIGITSLEN				; Copy digits length into ECX (counter)
		rep	movsb					; Copy score digits to scr buffer
		
		pop ebp
		pop esi						; Restore modified registers
		pop edi
		pop edx
		pop ecx
		pop eax
		ret						; Return to caller
		
; WrtCntr()
; Description: Write a string centered to the specified row
;
; Input: 
; ESI = location of source string
; ECX = length of string
; EDX = row number
;
; Output:
;
; Altered: EAX, EDI

wrtcntr:
	
		push eax					; Save modified registers
		push edi
		
		mov	eax, TERMWIDTH				; Copy screen TERMWIDTH value into EAX
		mul	edx					; Multiply it by the row number
		mov	edi, scr				; Set EDI to point to scr buffer
		add	edi, eax				; Position EDI to the specified row
		mov	eax, TERMWIDTH				; Copy TERMWIDTH back into EAX
		sub	eax, ecx				; Subract message length from TERMWIDTH
		shr	eax, 1					; Divide by two
		add 	edi, eax				; Add the correct number of spaces to center the message
		cld						; Clear directional flag to ensure destination pointer is increased, not decreased
		rep	movsb					; Copy intromsg into outbuf, one byte at a time
		
		pop edi						; Restore modified registers
		pop eax
		ret
				

;#########################################################################
;# GLOBAL START								##
;#########################################################################

global 	_start							; Used by linker to find entry point

_start:

; initializeTerminal
; The attributes of the TTY connected to stdin are retrieved, 
; and then canonical mode and input echoing are turned
; off. Similar to what ncurses calls "cbreak mode". The original 
; attributes are remembered so that they can be restored at the end.

		mov	edx, termios				; Load the address of termios into EDX
		mov	ecx, TCGETS				; Load the TCGETS value into ECX
		xor	ebx, ebx				; Zero the EBX register
		mov	eax, SC_ioctl
		int	0x80					; Perform system call
		mov	eax, [termios.lflag]			; Copy the value at termios.lflag into EAX
		push	eax					; Push original value onto the stack
		and	eax, byte ~(ICANON | ECHO)		; ~ computes the one's complement of its operand. Make changes to lflag
		mov	[termios.lflag], eax			; Copy the modified lflag value back into memory
		inc	ecx					; Increment ECX, so that TCGETS becomes TCSETS
		mov	eax, SC_ioctl
		int	0x80					; Perform system call
		pop	dword [termios.lflag]			; Pop original lflag value back into memory (no syscall, so no change)

; initializeTimers
; A do-nothing signal handler is installed for SIGALRM, and then an
; interval timer is set up to go off every x seconds.

		mov	eax, SC_sigaction
		cdq						; Convert double word to quad word. EAX becomes EDX:EAX
		mov	bl, SIGALRM				; Load SIGALRM value into low byte of EBX
		mov     ecx, sigact				; Move address of sigact into ECX (sigact points to ret instruction)
		int	0x80					; Perform system call
		mov	ecx, timer				; Load address of timer structure into ECX
		mov	eax, INTROSPEED * 1000			; Load the result of INTROSPEED * 1000 into EAX (controls speed of incoming stars)
		mov	[byte ecx + 4], eax			; Copy the result into the 4th byte of timer
		mov	[byte ecx + 12], eax			; And copy the result into the 12th byte of timer
		cdq						; Convert double word to quad word. EDX:EAX
		xor	ebx, ebx				; Zero the EBX register
		mov	eax, SC_setitimer
		int	0x80					; Perform system call

; initializeRnd
; The current time is used to initialize the pseduorandom-number generator

		mov	ebx, rndseed				; Copy the address of rndseed into EBX
		mov	eax, SC_gettimeofday 			; Copy the value of system call SC_gettimeofday into EAX
		int	0x80					; Perform system call. Current time is written to rndseed
	
; initializeScreen 
; Erase scr buffer (fill it with spaces)

		call erasescr
		
; draw welcome message

		call drawintromsg
		
; drawShip
; Set the ship's starting coordinates and draw it on the screen buffer
		mov	eax, SHIPSTART
		mov	[ship],eax
		call drawship
		
;#########################################################################
;# Enter Intro Main Loop						##
;#########################################################################

introloop:

;#########################################################################
;# getkey								##
;#########################################################################
; Examine the input queue. If a keystroke is waiting in there, then
; remove it and use it as this iteration's keystroke.
; If two keystrokes are waiting there, remove the first one and move
; the second one into its position

		mov	ecx, key				; Copy the address of key (key input queue) into ECX
		mov	al, [byte ecx + 1]			; Copy the second byte of key to AL
		or	al, al					; OR AL with itself
		jz	.readkey				; If zero (no key) jump to readkey procedure
		xor	edx, edx				; Otherwise, we have a key. Zero the EDX register
		cmp	dl, [byte ecx + 2]			; Check the third byte of key for a keystroke
		jz	.retlast				; If it's empty, jump to retlast
		xchg	dl, [byte ecx + 2]			; If not empy, move it into DL and move DL's value (zero) into the third byte of key
.retlast:	mov	[byte ecx + 1], dl			; Move whatever is in DL (zero or keystroke) into the second byte of key
.retkey:	mov	[ecx], al				; Copy the keystroke to the first byte of key
		jmp	short .endkeys				; Jump to endkeys routine

; Otherwise, check for an incoming character. If anything besides ESC
; is returned (including zero, indicating no keys have been pressed),
; then proceed with that key. Otherwise, check for a second
; character. If anything besides '[' or 'O' is returned, then put the
; character in the input queue and proceed with the ESC. Otherwise,
; check for a third character. If anything besides 'C' or 'D' is
; returned, then put it and the previous character into the input
; queue and proceed with the ESC. Otherwise, replace the arrow-key
; sequence with an 'm' or an 'n', as appropriate.

.readkey:	call	getkey					; Call the getkey routine
		cmp	al, ESC					; Compare AL with ESC
		jnz	.endkeys				; If not ESC, continue on with program
		inc	ecx					; Increment ECX. The next keystroke will be placed at key + 1
		call	getkey					; Call the getkey routine
		cmp	al, '['					; Compare AL with '['
		jz	.getthird				; If it is '[', jump to getthird
		cmp	al, 'O'					; Compare AL to '0'
		jnz	.endkeys				; If it's not zero, continue with program
.getthird:	inc	ecx					; Increment ECX. The next keystroke will be placed at key + 2
		call	getkey					; Call the getkey routine
		cmp	al, 'C'					; Check for right arrow ^[[C
		jz	.acceptarrow				; If it is 'C', jump to acceptarrow
		cmp	al, 'D'					; Check for left arrow ^[[D
		jnz	.endkeys				; If not, jump to end keys
.acceptarrow:	add	al, 'm' - 'C'				; Convert arrow key to an 'm' or 'n'. Add 'm' - 'C' (0x6D - 0x43 = 0x2A *) to AL
		movzx	eax, al					; movzc - Move and zero extend the register. Move AL into EAX and zero the remaining bits.
		mov	[byte ecx - 2], eax			; Copy EAX (AL) into the first byte of key
.endkeys:

; If a 'q' was retrieved, exit the program immediately. 

		cmp	al, 'q'					; Check if AL = 'q'
		jz	near leavegame				; If so, jump to leave game
		cmp	al, NULL				; Has the user pressed a key?
		jnz	maininit				; If so, call the main program
		
;#########################################################################
;# Form Stars								##
;#########################################################################

; Check if it's time to form a new star. If so, process the .formstar instructions. Otherwise, skip ahead

		mov	eax, [starspdctl]			; Move starspdctl value into EAX
		cmp	eax, FORMSPEED				; Compare it to FORMSPEED
		jl	.skipform				; Jump ahead if it's not time yet
								; Otherwise, spawn an alien
.formstar:	mov	[starspdctl], dword NULL			; Zero the spawning timer

.positionstar:
		xor	ecx, ecx
; Generate a random number and divide it by terminal width minus alien width
; Use the remainder as the star's starting coordinates
		mov	eax, [rndseed]				; Copy the value at rndseed into EAX. This value was set during the initialization of the program.

		mov	edx, 1103515245				; Copy large number into EDX
		mul	edx					; Multiply EDX by EAX and store the result int EDX:EAX
		add	eax, 12345				; Add number to EAX
		shl	eax, 1					; Shift all bits in EAX one to the left. The left most bit is shifted into the carry flag. Rightmost bit is cleared to zero.
		shr	eax, 1					; Shift all bits in EAX one to the right. The right most bit is shifted into the carry flag. Leftmost bit is cleared to zero.
		mov	[rndseed], eax				; Copy the jumbled up value back into rndseed. Jumbled value remains in EAX for the following instructions.
		mov	ebx, (TERMWIDTH - 60)
		
		xor	edx, edx				; Zero EDX register, where the remainder of division result will go.
		
		;xor	eax, eax
		div	ebx					; Perform division. EAX / 80. Remainder (0-19) goes into EDX (star's starting point)
		; Move star to its starting point 
		xor 	eax, eax				; Zero EAX register. Prepare it for star's new starting point.
		inc	edx					; Prevent star from starting at position 0 (won't exist)
		
		jp	.rightside				; If parity flag set (even), jump to .rightside
		add	eax, edx				; Add remainder of division of random number to starting position
		jmp	.leftside				; Otherwise, don't add anything. Leave star on left side.
		
.rightside	add	eax, edx				; Add remainder of division of random number to starting position
		add	eax, (TERMWIDTH - 20)			; Add 60 to put it on the right side

.leftside	mov	ebx, star				; Copy address of star table into EDX
		
		mov	ecx, dword [starcounter]		; Copy starcounter value into ECX
		
		lea	edx, [ebx+ecx*4]			; Add ( (counter - 1) * 4) to EBX to the current star's effective memory address
		
		mov 	[edx], eax				; Copy the star's starting point into the star's memory slot
		
		inc	dword [starcounter]			; Increment aliencounter for next time routine is called
		
		cmp	dword [starcounter], MAXSTARS		; Have we reached ten?
		jl	.continue				; Not yet? Jump out of loop
		mov	dword [starcounter], NULL		; Otherwise, reset counter to zero
		
.continue:	jmp	staradvance				; Skip passed the increment step below, as we zero'd the spawn timer at the beginning of the routine

.skipform:	inc dword [starspdctl]				; Increment spawn timer

;#########################################################################
;# Advance Stars							##
;#########################################################################
staradvance:
		xor	ecx, ecx
		mov	ecx, MAXSTARS				; Process # of aliens create
.advancestar	mov	ebx, star				; Copy the address of the star table into EDX
		dec 	ecx
		lea	edx, [ebx+ecx*4]			; Get the memory address of the current star
		inc	ecx
		; Check if no star exits
		cmp	[edx], dword NULL			; If zero, jump to .doloop which decrements ECX and jumps to start of loop
		jz	.doloop2				;

		add	dword [edx], TERMWIDTH			; Otherwise, advance. Add TERMWIDTH to star's coordinates
		cmp	dword [edx], ( TERMWIDTH * ( HEIGHT - 1) )	; Check if star has passed bottom row 
		jle	.doloop2				; If the star hasn't passed the bottom row, continue
		mov	[edx], dword NULL			; Otherwise, zero the star
		
.doloop2	loop	.advancestar				; Move remaining aliens forward


		
;#########################################################################
;# prepSCREEN								##
;#########################################################################
; The screen buffer is erased and then all components of the game are then drawn to it
		call	erasescr				; Erase screen buffer
		call	drawintromsg				; Draw welcome message and instructions
		call	drawship				; Draw ship
		call	drawstars				; Draw stars
		
;#########################################################################
;# REFRESH AND LOOP							##
;#########################################################################
; The refresh routine is called, which writes the scr buffer to outbuf and then prints outbuf to stdout.
; This needs to be called AFTER the terminal screen is erased, otherwise
; the alien ship will not make visual contact with the ship before exiting the game
		call	refresh					; Call the refresh procedure, which writes the output buffer to stdout
		
; The program goes to sleep until the next SIGALRM arrives, 
; whereupon it begins the next iteration of the main loop.
		push	SC_pause				; Push the SC_pause service routine value onto the stack
		pop	eax					; Pop it into EAX
		int  	0x80					; Perform system call.
		jmp	near introloop				; Jump back to the main loop
		
		
;#########################################################################
;# Initialize Main Program						##
;#########################################################################

maininit:

; initializeTerminal done in intro initialization

; initializeTimers
; Increase speed of game from INTROSPEED to GAMESPEED
; A do-nothing signal handler is installed for SIGALRM, and then an
; interval timer is set up to go off every x seconds.

		mov	eax, SC_sigaction
		cdq						; Convert double word to quad word. EAX becomes EDX:EAX
		mov	bl, SIGALRM				; Load SIGALRM value into low byte of EBX
		mov     ecx, sigact				; Move address of sigact into ECX (sigact points to ret instruction)
		int	0x80					; Perform system call
		mov	ecx, timer				; Load address of timer structure into ECX
		mov	eax, GAMESPEED * 1000			; Load the result of GAMESPEED * 1000 into EAX (0.025 seconds for fast lasers)
		mov	[byte ecx + 4], eax			; Copy the result into the 4th byte of timer
		mov	[byte ecx + 12], eax			; And copy the result into the 12th byte of timer
		cdq						; Convert double word to quad word. EDX:EAX
		xor	ebx, ebx				; Zero the EBX register
		mov	eax, SC_setitimer
		int	0x80					; Perform system call

; initializeRnd
; The current time is used to re-initialize the pseduorandom-number generator

		mov	ebx, rndseed				; Copy the address of rndseed into EBX
		mov	eax, SC_gettimeofday 			; Copy the value of system call SC_gettimeofday into EAX
		int	0x80					; Perform system call. Current time is written to rndseed
	
; initializeScreen 
; Erase scr buffer (fill it with spaces)

		call erasescr
		
; initializeAlienSpeed
		; check now done when decided whether or not to advance aliens
		;mov	[alienspeed], dword ALIENSPEED1		; Set initial speed of aliens for first half of game
		
; drawShip
; Set the ship's starting coordinates and draw it on the screen buffer
		mov	eax, SHIPSTART
		mov	[ship],eax
		call drawship
		

; drawScore
; Draw the scoreboard to the screen buffer
		call drawscore
		
; drawEnergy
; Under Construction

;#########################################################################
;# Enter Main Loop							##
;#########################################################################

mainloop:

;#########################################################################
;# getkey								##
;#########################################################################
; Examine the input queue. If a keystroke is waiting in there, then
; remove it and use it as this iteration's keystroke.
; If two keystrokes are waiting there, remove the first one and move
; the second one into its position

		mov	ecx, key				; Copy the address of key (key input queue) into ECX
		mov	al, [byte ecx + 1]			; Copy the second byte of key to AL
		or	al, al					; OR AL with itself
		jz	.readkey				; If zero (no key) jump to readkey procedure
		xor	edx, edx				; Otherwise, we have a key. Zero the EDX register
		cmp	dl, [byte ecx + 2]			; Check the third byte of key for a keystroke
		jz	.retlast				; If it's empty, jump to retlast
		xchg	dl, [byte ecx + 2]			; If not empy, move it into DL and move DL's value (zero) into the third byte of key
.retlast:	mov	[byte ecx + 1], dl			; Move whatever is in DL (zero or keystroke) into the second byte of key
.retkey:	mov	[ecx], al				; Copy the keystroke to the first byte of key
		jmp	short .endkeys				; Jump to endkeys routine

; Otherwise, check for an incoming character. If anything besides ESC
; is returned (including zero, indicating no keys have been pressed),
; then proceed with that key. Otherwise, check for a second
; character. If anything besides '[' or 'O' is returned, then put the
; character in the input queue and proceed with the ESC. Otherwise,
; check for a third character. If anything besides 'C' or 'D' is
; returned, then put it and the previous character into the input
; queue and proceed with the ESC. Otherwise, replace the arrow-key
; sequence with an 'm' or an 'n', as appropriate.

.readkey:	call	getkey					; Call the getkey routine
		cmp	al, ESC					; Compare AL with ESC
		jnz	.endkeys				; If not ESC, continue on with program
		inc	ecx					; Increment ECX. The next keystroke will be placed at key + 1
		call	getkey					; Call the getkey routine
		cmp	al, '['					; Compare AL with '['
		jz	.getthird				; If it is '[', jump to getthird
		cmp	al, 'O'					; Compare AL to '0'
		jnz	.endkeys				; If it's not zero, continue with program
.getthird:	inc	ecx					; Increment ECX. The next keystroke will be placed at key + 2
		call	getkey					; Call the getkey routine
		cmp	al, 'C'					; Check for right arrow ^[[C
		jz	.acceptarrow				; If it is 'C', jump to acceptarrow
		cmp	al, 'D'					; Check for left arrow ^[[D
		jnz	.endkeys				; If not, jump to end keys
.acceptarrow:	add	al, 'm' - 'C'				; Convert arrow key to an 'm' or 'n'. Add 'm' - 'C' (0x6D - 0x43 = 0x2A *) to AL
		movzx	eax, al					; movzc - Move and zero extend the register. Move AL into EAX and zero the remaining bits.
		mov	[byte ecx - 2], eax			; Copy EAX (AL) into the first byte of key
.endkeys:

; If a 'q' was retrieved, exit the program immediately. 

		cmp	al, 'q'					; Check if AL = 'q'
		jz	near leavegame				; If so, jump to leave game
		
;#########################################################################
;# moveSHIP								##
;#########################################################################
; The keystroke is retrieved, and, if appropriate, the program moves the ship left or right.

; First, check if the ship has been hit. If so, prevent it from moving
		cmp	dword [shipflash], 0			; See if the shipflash flag is still zero
		jnz	.endturn				; If not, do not let the player move

		mov	al, [key]				; Copy the current key into AL
		cmp	al, '4'					; Check if it's the digit '4'
		jz	.left					; If so, go left
		cmp	al, '6'					; Check if it's the digit '6'
		jz	.right					; If so, go right
		or	al, 'a' - 'A'				; Accept upper or lower case 
		cmp	al, 'n'					; 'n' or 'N'? 
		jz	.left					; If so, go left
		cmp	al, 'm'					; 'm' or 'M'?
		jnz	.endturn				; If not, directional keys not pressed, exit routine
.right:
		cmp	dword [ship], SHIPMAXRIGHT		; Too far right?
		jge	.endturn				; Jump if greater than or equal
		inc	dword [ship]				; Move ship to the right
		jmp	.endturn				; Skip to endturn
.left:
		cmp	dword [ship], SHIPMAXLEFT		; Too far left?
		jle	.endturn				; Jump if less than or equal to
		dec	dword [ship]				; Move ship to the left
		jmp	.endturn
.endturn:
		
;#########################################################################
;# moveALIENS								##
;#########################################################################

; If there are no aliens (invaders) on screen, process the .createalien instructions. Otherwise, skip ahead
		mov	eax, [invaders]				; Move the number of alien invaders into AL
		cmp	eax, dword NULL				; Compare it to NULL
		jnz	collcheck1				; If there is one or more aliens, check if they've been hit by a laser
								; Otherwise, execute the createaliens instructions
		mov	[fastalien], dword NULL			; Reset fastalien flag to zero
.createaliens:	mov	eax, [score]				; Copy current score into EAX
		cmp	eax, LEVEL1				; Check which level the player is in and spawn appropriate number of aliens
		jl	.onealien				; Still in level 0
		cmp	eax, LEVEL2
		jl	.onefastalien				; Still in level 1
		cmp	eax, LEVEL3
		jl	.twoaliens				; Still in level 2
		cmp	eax, LEVEL4
		jl	.onefastalien				; Still in level 3
		cmp	eax, LEVEL5
		jl	.fouraliens				; Still in level 4
		; Midgame
		;mov	[alienspeed], DWORD ALIENSPEED2		; Increase alien advance speed for second half of game
		cmp	eax, LEVEL6
		jl	.twofastaliens				; Still in level 5
		cmp	eax, LEVEL7
		jl	.sixaliens				; Still in level 6
		cmp	eax, LEVEL8
		jl	.twofastaliens				; Still in level 7
		cmp	eax, LEVEL9
		jl	.sixaliens				; Still in level 8
		cmp	eax, LEVEL10
		jl	.eightaliens				; Still in level 9
		jmp	.eightaliens				; Anything else? Spawn eight aliens.
.onealien:	mov	[invaders], dword 1 			; Spawn one alien (This value is decremented when aliens are destroyed)
		mov	[aliencounter], dword 1			; Set loop control (Won't change outside of this routine)
		jmp	.positionalien				; Jump ahead to positionaliens
.onefastalien	mov	[fastalien], dword NONZERO		; Set fastalien flag
		mov	[invaders], dword 1
		mov	[aliencounter], dword 1
		jmp	.positionalien
.twoaliens:	mov	[invaders], dword 2			; Spawn two aliens
		mov	[aliencounter], dword 2			; Set loop control
		jmp	.positionalien				; Jump to positionaliens
.twofastaliens	mov	[fastalien], dword NONZERO		; Set fastalien flag
		mov	[invaders], dword 2
		mov	[aliencounter], dword 2
		jmp	.positionalien
.fouraliens:	mov	[invaders], dword 4			; Spawn three aliens
		mov	[aliencounter], dword 4			; Set loop control
		jmp	.positionalien				; Jump to position aliens
.sixaliens:	mov	[invaders], dword 6
		mov	[aliencounter], dword 6			
		jmp	.positionalien
.eightaliens:	mov	[invaders], dword 8			; Spawn eight aliens
		mov	[aliencounter], dword 8			; Set loop control
								; Proceed to positionaliens

.positionalien:	xor	eax,eax					; Clear (zero) registers 
		xor	ebx,ebx
		xor	edx,edx
		mov	eax, dword TERMWIDTH			; Copy terminal width into EAX. DWORD to prevent floating point exceptions
		mov	ebx, dword [invaders]			; Copy the number of aliens into EBX. DWORD to prevent floating point exceptions
		div	ebx					; Divide terminal width by the number of aliens. 
								; Quotient goes into EAX.
		mov	ebp, eax				; Store unmodified quotient (screen divider) in EBP (for use in loop)
		mov	ebx, eax				; Move the quotient into EBX
		sub	ebx, ALIENWIDTH				; Subtract alien width. EBX will be used to divide random numbers from which we will use the remainder
		mov	ecx, [aliencounter]			; Set counter. Repeat below instructions for each alien
.getrandom:	mov	eax, [rndseed]				; Copy the value at rndseed into EAX. This value was set during the initialization of the program.
		mov	edx, 1103515245				; Copy large number into EDX
		mul	edx					; Multiply EDX by EAX and store the result int EDX:EAX
		add	eax, 12345				; Add number to EAX
		shl	eax, 1					; Shift all bits in EAX one to the left. The left most bit is shifted into the carry flag. Rightmost bit is cleared to zero.
		shr	eax, 1					; Shift all bits in EAX one to the right. The right most bit is shifted into the carry flag. Leftmost bit is cleared to zero.
		mov	[rndseed], eax				; Copy the jumbled up value back into rndseed. Jumbled value remains in EAX for the following instructions.
		
		xor	edx, edx				; Zero EDX register, where the remainder of division result will go.
		div	ebx					; Divide random number by the quotient minus alienwidth determined before entering the loop. 
								; Remainder now in EDX
		mov	edi, dword edx				; Save remainder EDX in EDI
		xor	eax, eax
		mov	eax, dword ebp				; Copy unmodified quotient into EAX
		dec	ecx					; Decrement ECX for calculation
		mul	ecx					; Multiply by counter - 1. Result stored in EAX.
		inc	ecx					; Restore ECX counter
		add	eax, edi				; Add the result to EAX to get alien's starting point

		add	eax, ALIENPADDING			; Prevent alien from being 0 + being cut off on the left side of the screen.
		
		mov	edx, alien				; Copy address of alien table into EDX
		
		dec	ecx					; Decrement counter (for memory calculation)
		lea	edx, [edx+ecx*4]			; Add ( (counter - 1) * 4) to EBX to the current alien's effective memory address
		inc	ecx					; Restore counter
		
		mov 	[edx], dword eax				; Copy the alien's starting point into the alien's memory address
		loop	.getrandom				; Loop back to create another alien until counter reaches 0


		
; Collision check #1
; Before alien (might) move
collcheck1:	call	lasercheck
	
		
; First, check if the ship has been hit
		cmp	dword [shipflash], NULL			; Has the ship been hit?
		jnz	.shipflashing				; If so, don't move the aliens
		
; Check if it's time for the aliens to move forward (based on timer)	
.advancecheck:	cmp	[fastalien], byte NULL			; Is it a fast alien?
		jnz	.fast					; If so, increase speed of advancing aliens
		cmp	[alienspdctl], byte ALIENSPEED1		; Otherwise, use normal speed
		jl	.finishalien				; Check if the aliens should advance or wait 
		jmp	.proceed
.fast		cmp	[alienspdctl], byte ALIENSPEED2		; signal alarm from the operating system (this paces the attack)
		jl	.finishalien				; If not, skip the routine and increment alienspdctl
.proceed:							; Otherwise, continue
		mov	byte [alienspdctl], 0			; Time for alien to move forward. Reset alienspdctl to zero.
		mov	ecx, [aliencounter]			; Process # of aliens created
.advancealien	mov	ebx, alien				; Copy address of alien into EDX
		dec 	ecx
		lea	edx, [ebx+ecx*4]			; Get the memory address of the current alien
		inc	ecx
		; Check if alien has already been destroyed
		cmp	[edx], dword NULL			; If zero, jump to .doloop which decrements ECX and jumps to start of loop
		jz	.doloop2				;
		; Check if alien is flashing (just been hit)
		mov	ebx, alienflash				; Copy address of alienflash table into EBX
		dec	ecx
		lea	ebp, [ebx+ecx*4]			; Get effective address of the current alien's slot in the alienflash table
		inc	ecx
		cmp	[ebp], dword NULL			; Compare it to zero
		jnz	.doloop2				; If not zero (ie: alien is flashing), do not move, just skip to next alien.

		add	dword [edx], TERMWIDTH			; Advance. Add TERMWIDTH to alien's coordinates
		cmp	dword [edx], ( TERMWIDTH * ( HEIGHT - ALIENHEIGHT - 1 ) )	; Check if alien has invaded successfully (touched bottom row) 
		jle	.doloop2				; If the alien hasn't breached past the bottom row, continue
		;jmp	alienswin				; Otherwise, the aliens have won. Exit game.
		inc	DWORD [alienwin]			; Instead of exiting the loop immediately, set the alienwin flag and allow
								; the remaining aliens to move forward. This will prevent the aliens
								; from appearing to land unevenly 
		
.doloop2	loop	.advancealien				; Move remaining aliens forward

		
.finishalien:	inc	byte [alienspdctl]			; Increment the timer control value
.shipflashing:

; Check if the aliens have won
		cmp	[alienwin], DWORD NULL			; alienwin still contains zero?
		jnz	alienswin				; If not, the aliens have won.

; Collision check #2
; After alien moves
collcheck2:	call	lasercheck
		

;#########################################################################
;# LASER								##
;#########################################################################
; Check if a laser exists. If so, subtract TERMWIDTH from laser and see if it goes out of bounds (negative number). If so, zero it.
; If no laser exists, check if the user hit the fire key. If so, fire the laser.

		mov 	eax, [laser]				; Move the value at laser into EAX
		or 	eax, eax				; Check if it's zero (no laser exists)
		jz	.fire					; If so, see if user fired
; Check if the laser will pass into outer space. If not, advance it. Otherwise, clear it.
.advance:	
		sub	eax, dword TERMWIDTH			; Subract width to move laser up one row
		js	.clear					; Check if laser has passed the top row to outerspace. If so, erase it
								; (JS = Jump if Sign flag set) 
		mov	[laser], eax				; Copy new value into laser
		jmp	.finishlaser				; Do not fire if laser already exists, instead jump to .finishlaser
.fire:		; Check if the ship has been hit
		cmp	dword [shipflash], NULL			; Ship flash flag been set?
		jnz	.finishlaser				; If so, do not allow player to fire laser
		mov	dl, [key]				; Retrieve current keystroke
		cmp	dl, ' '					; Check if user pressed the spacebar
		jnz	.finishlaser				; If not, just move on
		mov	ecx, [ship]				; Otherwise, move ship's coordinates into ECX
		sub	ecx, dword TERMWIDTH			; Subract one row
		mov	[laser], ecx				; Position laser
		jmp 	.finishlaser				; END
.clear:  	mov	dword [laser], 0			; Nullify laser
.finishlaser:
		
;#########################################################################
;# prepSCREEN								##
;#########################################################################
; The screen buffer is erased and then all components of the game are then drawn to it
		call	erasescr				; Erase screen buffer
		call	flashship				; Draw ship
		call	flashalien				; See if an alien should flash. If not, draw them normally.
		call	drawlaser				; Draw laser
		call 	drawscore				; Draw scoreboard
		
;#########################################################################
;# REFRESH AND LOOP							##
;#########################################################################
; The refresh routine is called, which writes the scr buffer to outbuf and then prints outbuf to stdout.
; This needs to be called AFTER the terminal screen is erased, otherwise
; the alien ship will not make visual contact with the ship before exiting the game
		call	refresh					; Call the refresh procedure, which writes the output buffer to stdout
		
; The program goes to sleep until the next SIGALRM arrives, 
; whereupon it begins the next iteration of the main loop.
		push	SC_pause				; Push the SC_pause service routine value onto the stack
		pop	eax					; Pop it into EAX
		int  	0x80					; Perform system call.
		jmp	near mainloop				; Jump back to the main loop
		
;#########################################################################
;# ALIENS WIN								##
;#########################################################################
; Code to execute if the player fails miserably
alienswin:	call erasescr					; Erase the screen buffer to prepare for final frame
		; Write losing message
		mov esi, alienswin1
		mov ecx, ALIENSWIN1LEN
		mov edx, CENTERROW
		call wrtcntr
		; Redraw all elements to prevent blank window
		call drawship					; Draw spaceship
		call flashalien					; Draw aliens in their final positions
		call drawscore					; Draw final score
		call refresh					; This may print unwanted stuff to the screen. BUGCHECK
		jmp leavegame					; Jump to leavegame

;#########################################################################
;# HUMANS WIN								##
;#########################################################################
; Code to execute if player succeeds wonderfully
playerwins:	; Write success message
		mov esi, playerwins1				; Copy message address into ESI
		mov ecx, PLAYERWINS1LEN				; Copy length into ECX
		mov edx, CENTERROW				; Copy center row into EDX (height / 2)
		call wrtcntr					; Call the write center routine
		mov esi, playerwins2				; Copy 2nd message address into ESI
		mov ecx, PLAYERWINS2LEN				; Copy lenght to ECX
		mov edx, CENTERROW + 1				; Copy to center row + 1
		call wrtcntr					; Call the write center routine
		call drawscore					; Draw updated score before exiting
		call refresh					; Refresh the display
		
;#########################################################################
;# EXIT									##
;#########################################################################
;The program restores the TTY to its original settings, and exits
leavegame:

		mov	edx, termios					; Load the address of termios into EDX
		mov	ecx, TCSETS					; Load the TCSETS value into ECX
		xor	ebx, ebx					; Zero the EBX register
		mov	eax, SC_ioctl
		int	0x80						; Perform system call
		xchg	eax, ebx					; Swap EAX and EBX
		inc	eax						; Increment EAX to 1. Exit syscall = 1
		mov 	ebx, 0						; Load EBX with 0. Return zero.
		int	0x80						; Perform system call
	

	


	

	