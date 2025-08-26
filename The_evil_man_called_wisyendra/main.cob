IDENTIFICATION DIVISION.
       PROGRAM-ID. BANKING.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-FILE ASSIGN TO "input.txt"
               ORGANIZATION IS LINE SEQUENTIAL.
           SELECT ACC-FILE ASSIGN TO "accounts.txt"
               ORGANIZATION IS LINE SEQUENTIAL.
           SELECT TMP-FILE ASSIGN TO "temp.txt"
               ORGANIZATION IS LINE SEQUENTIAL.
           SELECT OUT-FILE ASSIGN TO "output.txt"
               ORGANIZATION IS LINE SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.
       FD IN-FILE.
       01 IN-RECORD                 PIC X(18).

       FD ACC-FILE.
       01 ACC-RECORD-RAW            PIC X(18).

       FD TMP-FILE.
       01 TMP-RECORD                PIC X(18).

       FD OUT-FILE.
       01 OUT-RECORD                PIC X(200).

       WORKING-STORAGE SECTION.
       77 IN-ACCOUNT                PIC 9(6).
       77 IN-ACTION                 PIC X(3).
       77 IN-AMOUNT                 PIC 9(6)V99.

       77 ACC-ACCOUNT               PIC 9(6).
       77 ACC-BALANCE               PIC 9(6)V99.

       77 TMP-BALANCE               PIC 9(6)V99.
       77 MATCH-FOUND               PIC X VALUE "N".
       77 UPDATED                   PIC X VALUE "N".

       77 FORMATTED-AMOUNT          PIC 9(6).99.
       77 BALANCE-TEXT              PIC X(20).
       77 BALANCE-ALPHA             PIC X(15).

       *> --- Currency conversion (Rai -> IDR) ---
       77 RAI-TO-IDR                PIC 9(9)   VALUE 119714660.
       77 IDR-AMOUNT                PIC 9(15)V99.
       77 IDR-FMT                   PIC Z(15).99.
       77 IDR-TEXT                  PIC X(60).

*> --- Interest ---
77 CMD-LINE                 PIC X(256) VALUE SPACES.
77 ARG-COUNT                PIC 9(4)   VALUE 0.
77 APPLY-COUNT              PIC 9(4)   VALUE 0.
77 INTEREST-FOUND           PIC 9(4)   VALUE 0.
77 INTEREST-RATE            PIC 9V9999 VALUE 0.10.
77 I-ACC                    PIC 9(6).
77 I-AMT                    PIC 9(6)V99.


       PROCEDURE DIVISION.

       MAIN.

ACCEPT CMD-LINE FROM COMMAND-LINE
MOVE 0 TO INTEREST-FOUND
INSPECT CMD-LINE TALLYING INTEREST-FOUND FOR ALL "-apply-interest"
IF INTEREST-FOUND > 0
    PERFORM INTEREST-SERVICE
    STOP RUN
END-IF
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
           PERFORM WRITE-OUTPUT
           PERFORM FINALIZE
           STOP RUN.

       READ-INPUT.
           OPEN INPUT IN-FILE
           READ IN-FILE AT END
               MOVE "NO INPUT" TO OUT-RECORD
               PERFORM WRITE-OUTPUT
               STOP RUN
           END-READ
           CLOSE IN-FILE

           MOVE IN-RECORD(1:6)  TO IN-ACCOUNT
           MOVE IN-RECORD(7:3)  TO IN-ACTION
           MOVE FUNCTION NUMVAL(IN-RECORD(10:9)) TO IN-AMOUNT.

       PROCESS-RECORDS.
           OPEN INPUT  ACC-FILE
           OPEN OUTPUT TMP-FILE
           PERFORM UNTIL 1 = 2
               READ ACC-FILE
                   AT END
                       EXIT PERFORM
                   NOT AT END
                       MOVE ACC-RECORD-RAW(1:6) TO ACC-ACCOUNT
                       MOVE FUNCTION NUMVAL(ACC-RECORD-RAW(10:9)) TO ACC-BALANCE
                       IF ACC-ACCOUNT = IN-ACCOUNT
                           MOVE "Y" TO MATCH-FOUND
                           PERFORM APPLY-ACTION
                       ELSE
                           WRITE TMP-RECORD FROM ACC-RECORD-RAW
                       END-IF
               END-READ
           END-PERFORM
           CLOSE ACC-FILE
           CLOSE TMP-FILE.

       APPLY-ACTION.
           MOVE ACC-BALANCE TO TMP-BALANCE
           EVALUATE IN-ACTION
               WHEN "DEP"
                   ADD IN-AMOUNT TO TMP-BALANCE
                   PERFORM WRITE-UPDATED-RECORD
                   MOVE "DEPOSIT OK. NEW BALANCE: " TO BALANCE-TEXT
                   PERFORM BUILD-OUT-RECORD
                   MOVE "Y" TO UPDATED
               WHEN "WDR"
                   IF IN-AMOUNT > TMP-BALANCE
                       MOVE "INSUFFICIENT FUNDS. CURRENT BALANCE: " TO BALANCE-TEXT
                       MOVE ACC-BALANCE TO TMP-BALANCE
                       PERFORM BUILD-OUT-RECORD
                   ELSE
                       SUBTRACT IN-AMOUNT FROM TMP-BALANCE
                       PERFORM WRITE-UPDATED-RECORD
                       MOVE "WITHDRAWAL OK. NEW BALANCE: " TO BALANCE-TEXT
                       PERFORM BUILD-OUT-RECORD
                       MOVE "Y" TO UPDATED
                   END-IF
               WHEN "BAL"
                   MOVE "BALANCE: " TO BALANCE-TEXT
                   PERFORM BUILD-OUT-RECORD
               WHEN OTHER
                   MOVE "UNKNOWN ACTION" TO OUT-RECORD
           END-EVALUATE.

       WRITE-UPDATED-RECORD.
           MOVE ACC-ACCOUNT      TO TMP-RECORD(1:6)
           MOVE "BAL"            TO TMP-RECORD(7:3)
           MOVE TMP-BALANCE      TO FORMATTED-AMOUNT
           MOVE FORMATTED-AMOUNT TO TMP-RECORD(10:9)
           WRITE TMP-RECORD.

       BUILD-OUT-RECORD.
           MOVE SPACES TO OUT-RECORD
           MOVE TMP-BALANCE      TO FORMATTED-AMOUNT
           MOVE FORMATTED-AMOUNT TO BALANCE-ALPHA
           *> Compute IDR
           COMPUTE IDR-AMOUNT = TMP-BALANCE * RAI-TO-IDR
           MOVE IDR-AMOUNT TO IDR-FMT
           MOVE " | ≈ IDR Rp " TO IDR-TEXT(1:12)
           MOVE IDR-FMT         TO IDR-TEXT(13:17)
           STRING BALANCE-TEXT  DELIMITED SIZE
                  BALANCE-ALPHA DELIMITED SIZE
                  IDR-TEXT      DELIMITED SIZE
                  INTO OUT-RECORD.

       APPEND-ACCOUNT.
           OPEN EXTEND ACC-FILE
           MOVE IN-ACCOUNT       TO ACC-RECORD-RAW(1:6)
           MOVE "BAL"            TO ACC-RECORD-RAW(7:3)
           MOVE IN-AMOUNT        TO FORMATTED-AMOUNT
           MOVE FORMATTED-AMOUNT TO ACC-RECORD-RAW(10:9)
           WRITE ACC-RECORD-RAW
           CLOSE ACC-FILE.

       WRITE-OUTPUT.
           OPEN OUTPUT OUT-FILE
           WRITE OUT-RECORD
           CLOSE OUT-FILE.

       

INTEREST-SERVICE.
    DISPLAY "Starting interest service (every 23s). Rate: " INTEREST-RATE
    PERFORM WITH TEST AFTER UNTIL 1 = 2
        PERFORM APPLY-INTEREST-TO-ALL
        CALL "SYSTEM" USING "sleep 23"
    END-PERFORM.

APPLY-INTEREST-TO-ALL.
    OPEN INPUT  ACC-FILE
    OPEN OUTPUT TMP-FILE
    PERFORM UNTIL 1 = 2
        READ ACC-FILE
            AT END
                EXIT PERFORM
            NOT AT END
                MOVE ACC-RECORD-RAW(1:6)                 TO I-ACC
                MOVE FUNCTION NUMVAL(ACC-RECORD-RAW(10:9)) TO I-AMT
                COMPUTE TMP-BALANCE ROUNDED = I-AMT + (I-AMT * INTEREST-RATE)
                MOVE I-ACC              TO TMP-RECORD(1:6)
                MOVE "BAL"              TO TMP-RECORD(7:3)
                MOVE TMP-BALANCE        TO FORMATTED-AMOUNT
                MOVE FORMATTED-AMOUNT   TO TMP-RECORD(10:9)
                WRITE TMP-RECORD
        END-READ
    END-PERFORM
    CLOSE ACC-FILE
    CLOSE TMP-FILE
    CALL "SYSTEM" USING "mv temp.txt accounts.txt".

       FINALIZE.
           IF UPDATED = "Y"
               CALL "SYSTEM" USING "mv temp.txt accounts.txt"
           END-IF.
