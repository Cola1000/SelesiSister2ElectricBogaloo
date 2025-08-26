       IDENTIFICATION DIVISION.
       PROGRAM-ID. BANKING.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-FILE ASSIGN TO "input.txt".
           SELECT ACC-FILE ASSIGN TO "accounts.txt"
               ORGANIZATION IS LINE SEQUENTIAL.
           SELECT TMP-FILE ASSIGN TO "temp.txt"
               ORGANIZATION IS LINE SEQUENTIAL.
           SELECT OUT-FILE ASSIGN TO "output.txt"
               ORGANIZATION IS LINE SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.

       FD IN-FILE.
       01 IN-RECORD             PIC X(15).

       FD ACC-FILE.
       01 ACC-RECORD-RAW        PIC X(15).

       FD TMP-FILE.
       01 TMP-RECORD            PIC X(15).

       FD OUT-FILE.
       01 OUT-RECORD            PIC X(80).

       WORKING-STORAGE SECTION.
       77 IN-ACCOUNT            PIC 9(6).
       77 IN-ACTION             PIC X(3).
       77 IN-AMOUNT             PIC 9(6)V99.

       77 ACC-ACCOUNT           PIC 9(6).
       77 ACC-ACTION            PIC X(3).
       77 ACC-BALANCE           PIC 9(6)V99.

       77 TMP-BALANCE           PIC 9(6)V99.
       77 MATCH-FOUND           PIC X VALUE "N".
       77 UPDATED               PIC X VALUE "N".

       77 FORMATTED-AMOUNT      PIC 9(6).99.
       77 BALANCE-TEXT          PIC X(20).

       77 BALANCE-ALPHA         PIC X(15).

       PROCEDURE DIVISION.

       MAIN.
           PERFORM READ-INPUT
           PERFORM PROCESS-RECORDS
           IF MATCH-FOUND = "N"
               IF IN-ACTION = "NEW"
                   PERFORM APPEND-ACCOUNT
                   MOVE "ACCOUNT CREATED" TO OUT-RECORD
               ELSE
                   MOVE "ACCOUNT NOT FOUND" TO OUT-RECORD
               END-IF
           END-IF
           PERFORM FINALIZE
           STOP RUN.

       READ-INPUT.
           OPEN INPUT IN-FILE
           READ IN-FILE AT END
               DISPLAY "NO INPUT"
               STOP RUN
           END-READ
           CLOSE IN-FILE

           MOVE IN-RECORD(1:6) TO IN-ACCOUNT
           MOVE IN-RECORD(7:3) TO IN-ACTION
           MOVE FUNCTION NUMVAL(IN-RECORD(10:9)) TO IN-AMOUNT.

       PROCESS-RECORDS.
           OPEN INPUT ACC-FILE
           OPEN OUTPUT TMP-FILE
           PERFORM UNTIL MATCH-FOUND = "Y"
               READ ACC-FILE
                   AT END
                       EXIT PERFORM
                   NOT AT END
                       MOVE ACC-RECORD-RAW(1:6) TO ACC-ACCOUNT
                       MOVE FUNCTION NUMVAL(ACC-RECORD-RAW(10:9))
                           TO ACC-BALANCE
                       IF ACC-ACCOUNT = IN-ACCOUNT
                           MOVE "Y" TO MATCH-FOUND
                           PERFORM APPLY-ACTION
                       ELSE
                           WRITE TMP-RECORD FROM ACC-RECORD-RAW
                       END-IF
           END-PERFORM
           CLOSE ACC-FILE
           CLOSE TMP-FILE.


       APPLY-ACTION.
           MOVE ACC-BALANCE TO TMP-BALANCE
           EVALUATE IN-ACTION
               WHEN "DEP"
                   SUBTRACT IN-AMOUNT FROM TMP-BALANCE
                   MOVE "DEPOSITED MONEY" TO OUT-RECORD
               WHEN "WDR"
                   ADD IN-AMOUNT TO TMP-BALANCE
                   MOVE "WITHDREW MONEY" TO OUT-RECORD
               WHEN "BAL"
                   MOVE SPACES TO OUT-RECORD
                   MOVE "BALANCE: " TO BALANCE-TEXT
                   MOVE TMP-BALANCE TO FORMATTED-AMOUNT
                   MOVE FORMATTED-AMOUNT TO BALANCE-ALPHA
                   STRING BALANCE-TEXT DELIMITED SIZE
                          BALANCE-ALPHA DELIMITED SIZE
                          INTO OUT-RECORD
               WHEN OTHER
                   MOVE "UNKNOWN ACTION" TO OUT-RECORD
           END-EVALUATE

           MOVE IN-ACCOUNT TO TMP-RECORD(1:5)
           MOVE IN-ACTION  TO TMP-RECORD(6:3)
           MOVE TMP-BALANCE TO FORMATTED-AMOUNT
           MOVE FORMATTED-AMOUNT TO TMP-RECORD(11:9)

           WRITE TMP-RECORD
           MOVE "Y" TO UPDATED.

       APPEND-ACCOUNT.
           OPEN EXTEND ACC-FILE
           MOVE IN-ACCOUNT TO ACC-RECORD-RAW(1:5)
           MOVE IN-ACTION  TO ACC-RECORD-RAW(6:3)
           MOVE IN-AMOUNT TO FORMATTED-AMOUNT
           MOVE FORMATTED-AMOUNT TO ACC-RECORD-RAW(11:9)

           WRITE ACC-RECORD-RAW
           CLOSE ACC-FILE.

       FINALIZE.
           IF UPDATED = "Y"
               CALL "SYSTEM" USING "mv temp.txt accounts.txt"
           END-IF
           OPEN OUTPUT OUT-FILE
           CLOSE OUT-FILE.

