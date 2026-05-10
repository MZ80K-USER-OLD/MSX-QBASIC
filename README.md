# MSX QBASIC
MSX QBASIC is a structured BASIC for the MSX2 that runs on MSX-DOS2.

?To optimize performance, only integer types are supported for numerical values. Additionally, only one-dimensional arrays are supported.
Screen input and output rely on MSX-BIOS and MSX-BASIC.
In cases where display speed is particularly critical, such as with text editors, the VDP may be controlled directly.
File I/O and the memory mapper rely on MSX-DOS2.
?
?The syntax conforms to MSX-BASIC but has been extended to support structured programming.
The following structured control statements are available:
IF ~ THEN ~ ELSE ~ END-IF
WHILE ~ WEND
REPEAT ~ UNTIL

GOTO and GOSUB statements can specify labels.</br>
Labels are strings beginning with an asterisk (*) as like  *LABEL. .

Procedure definition using, 
PROC ~ END PROC.
Procedures can take arguments.
Procedures are called using the CALL statement,
CALL  DISPCHAR(ARG1,ARG2, ARG3) 

Function definition using,
 FUNC ~ END FUNC
Using labels

User-defined data types can be defined.

2. Modified versions of the source code must explicitly state that they have been modified,
   and must not be presented as if they were the original software.

3. This notice must not be removed or altered from any distribution of the source code.
