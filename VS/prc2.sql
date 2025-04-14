-- Loan Books From Reservation
-- The purpose of this procedure is to renew the membership of a specific member by checking their current membership status and extending the membership period based on the chosen renewal plan. It first fetches the member's data, then calculates the new start and end dates for the membership based on whether the member is currently active or expired. The procedure updates the member's record with the new dates and inserts a renewal record into the MemberRenewal table, while handling errors and ensuring data integrity with a rollback in case of failure.
CREATE OR REPLACE PROCEDURE prc_loan_reserved_books (v_reservation_id IN CHAR) IS
    v_member_id     Member.MemberID%TYPE;
    v_book_id       Book.BookID%TYPE;
    v_book_title    Book.Title%TYPE;
    v_newLoanId     Loan.LoanID%TYPE;
    v_newLoanDate   DATE;
    v_newDueDate    DATE;
    v_resStatus    	ReservationDetail.Status%TYPE;

    CURSOR resBookCursor IS
        SELECT rd.BookID, b.Title
        FROM ReservationDetail rd
        JOIN Book b ON rd.BookID = b.BookID
        WHERE rd.ReservationID = v_reservation_id;

BEGIN
    SELECT MemberID INTO v_member_id
    FROM Reservation
    WHERE ReservationID = v_reservation_id;

    v_newLoanId := 'LOA' || TO_CHAR(loan_seq.NEXTVAL, 'FM0000000');
    v_newLoanDate := SYSDATE;
    v_newDueDate := SYSDATE + 14;

    INSERT INTO Loan (LoanID, LoanDate, DueDate, MemberID)
    VALUES (v_newLoanId, v_newLoanDate, v_newDueDate, v_member_id);

    OPEN resBookCursor;
    LOOP
        FETCH resBookCursor INTO v_book_id, v_book_title;
        EXIT WHEN resBookCursor%NOTFOUND;

		SELECT Status INTO v_resStatus
		FROM ReservationDetail
		WHERE ReservationID = v_reservation_id AND BookID = v_book_id;

		IF v_resStatus = 'NOT AVAILABLE' THEN
			ROLLBACK;
			RAISE_APPLICATION_ERROR(-20000, 'Book: ' || v_book_id || ' from Reservation: ' || v_reservation_id || ' is not available!');
		END IF;

        INSERT INTO LoanDetail (LoanID, BookID, Status)
        VALUES (v_newLoanId, v_book_id, 'BORROWED');
    END LOOP;
    CLOSE resBookCursor;

    UPDATE Reservation
    SET ReservationStatus = 'COMPLETED'
    WHERE ReservationID = v_reservation_id;

    COMMIT;
	
	DBMS_OUTPUT.PUT_LINE('');
	DBMS_OUTPUT.PUT_LINE('Loan created successfully from reservation!');
	DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('========================================');
	DBMS_OUTPUT.PUT_LINE('              LOAN DETAILS               ');
	DBMS_OUTPUT.PUT_LINE('========================================');
	DBMS_OUTPUT.PUT_LINE(RPAD('Loan ID', 15) || ': ' || v_newLoanId);
	DBMS_OUTPUT.PUT_LINE(RPAD('Member ID', 15) || ': ' || v_member_id);
	DBMS_OUTPUT.PUT_LINE(RPAD('Loan Date', 15) || ': ' || TO_CHAR(v_newLoanDate, 'DD-MON-YYYY'));
	DBMS_OUTPUT.PUT_LINE(RPAD('Due Date', 15) || ': ' || TO_CHAR(v_newDueDate, 'DD-MON-YYYY'));
	DBMS_OUTPUT.PUT_LINE('----------------------------------------');
	DBMS_OUTPUT.PUT_LINE(' Book(s) Borrowed:');
	DBMS_OUTPUT.PUT_LINE('----------------------------------------');

    OPEN resBookCursor;
    LOOP
        FETCH resBookCursor INTO v_book_id, v_book_title;
        EXIT WHEN resBookCursor%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE('  - ' || v_book_id || ' | ' || v_book_title);
    END LOOP;
    CLOSE resBookCursor;

    DBMS_OUTPUT.PUT_LINE('========================================');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Reservation ID not found: ' || v_reservation_id);
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/


SELECT * FROM ReservationDetail ORDER BY ReservationID DESC;

INSERT INTO Reservation VALUES ('RES0000101', SYSDATE, 'PENDING', NULL, NULL, 'MEM0000001');
INSERT INTO ReservationDetail VALUES ('RES0000101', 'BOK0000005', SYSDATE, 'AVAILABLE');
INSERT INTO ReservationDetail VALUES ('RES0000101', 'BOK0000002', SYSDATE, 'NOT AVAILABLE');
INSERT INTO ReservationDetail VALUES ('RES0000101', 'BOK0000004', SYSDATE, 'NOT AVAILABLE');
COMMIT;

EXEC prc_loan_reserved_books ('RES0000101');

-- ------------------------------------------------------------------------------------------------------------------------

-- latest in docs!!!!
SET SERVEROUTPUT ON;

CREATE OR REPLACE PROCEDURE prc_loan_books (p_member_id IN CHAR, p_book_list IN VARCHAR) IS
    v_new_loan_id   Loan.LoanID%TYPE;
    v_loan_date     DATE := SYSDATE;
    v_due_date      DATE := SYSDATE + 14;
    v_book_id       Book.BookID%TYPE;
    v_pos           NUMBER := 1;
    v_next_pos      NUMBER;
    v_book_str      VARCHAR(100);
    v_book_copies   Book.AvailableCopies%TYPE;
   
BEGIN
    DECLARE
        v_temp_str VARCHAR(100) := p_book_list || ',';
        v_count NUMBER := 0;
        v_pos_check NUMBER := 1;
        v_next_pos_check NUMBER;
    BEGIN
        LOOP
            v_next_pos_check := INSTR(v_temp_str, ',', v_pos_check);
            EXIT WHEN v_next_pos_check = 0;
            v_count := v_count + 1;
            v_pos_check := v_next_pos_check + 1;
        END LOOP;

        IF v_count > 5 THEN
            RAISE_APPLICATION_ERROR(-20001, 'You can only loan up to 5 books at a time.');
        END IF;
    END;

    v_new_loan_id := 'LOA' || TO_CHAR(loan_seq.NEXTVAL, 'FM0000000');

    INSERT INTO Loan (LoanID, LoanDate, DueDate, MemberID)
    VALUES (v_new_loan_id, v_loan_date, v_due_date, p_member_id);

    LOOP
        v_next_pos := INSTR(p_book_list, ',', v_pos);
        IF v_next_pos = 0 THEN
            v_book_str := TRIM(SUBSTR(p_book_list, v_pos));
        ELSE
            v_book_str := TRIM(SUBSTR(p_book_list, v_pos, v_next_pos - v_pos));
        END IF;

        SELECT BookID, AvailableCopies INTO v_book_id, v_book_copies
        FROM Book
        WHERE BookID = v_book_str;
      
      IF v_book_copies <= 0 THEN
         ROLLBACK;
         RAISE_APPLICATION_ERROR(-20000, 'Book: ' || v_book_id || ' do not have available copies');
      END IF;
      
      INSERT INTO LoanDetail (LoanID, BookID, Status)
      VALUES (v_new_loan_id, v_book_id, 'BORROWED');
      
      UPDATE Book
      SET AvailableCopies = AvailableCopies - 1,
         BorrowedCount = BorrowedCount + 1
      WHERE BookID = v_book_id;
      
        EXIT WHEN v_next_pos = 0;
        v_pos := v_next_pos + 1;
    END LOOP;

    COMMIT;
   
    DBMS_OUTPUT.PUT_LINE('Loan created successfully.');
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('              LOAN DETAILS              ');
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('Loan ID       : ' || v_new_loan_id);
    DBMS_OUTPUT.PUT_LINE('Member ID     : ' || p_member_id);
    DBMS_OUTPUT.PUT_LINE('Loan Date     : ' || TO_CHAR(v_loan_date, 'DD-MON-YYYY'));
    DBMS_OUTPUT.PUT_LINE('Due Date      : ' || TO_CHAR(v_due_date, 'DD-MON-YYYY'));
    DBMS_OUTPUT.PUT_LINE('----------------------------------------');
    DBMS_OUTPUT.PUT_LINE(' Book(s) Borrowed:');
    DBMS_OUTPUT.PUT_LINE('----------------------------------------');

    FOR book_rec IN (
        SELECT b.BookID, b.Title
        FROM Book b
        JOIN LoanDetail ld ON b.BookID = ld.BookID
        WHERE ld.LoanID = v_new_loan_id
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('- ' || book_rec.BookID || ' | ' || book_rec.Title);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('========================================');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error: BookID(S) not found.');
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Unexpected Error: ' || SQLERRM);
END;
/


select * from book where bookid in ('BOK0000002', 'BOK0000003', 'BOK0000005');
EXEC prc_loan_books('MEM0000005', 'BOK0000010,BOK0000009,BOK0000011');





-- !!!!
CREATE OR REPLACE PROCEDURE prc_loan_books (v_member_id IN Member.MemberID%TYPE, v_book_list IN SYS.ODCIVARCHAR2LIST) IS
    v_newLoanId    Loan.LoanID%TYPE;
    v_loanDate     DATE := SYSDATE;
    v_dueDate      DATE := SYSDATE + 14;
BEGIN
    v_newLoanId := 'LOA' || TO_CHAR(loan_seq.NEXTVAL, 'FM0000000');

    INSERT INTO Loan (LoanID, LoanDate, DueDate, MemberID)
    VALUES (v_newLoanId, v_loanDate, v_dueDate, v_member_id);

    FOR i IN 1 .. v_book_list.COUNT LOOP
        DECLARE
            v_book_id Book.BookID%TYPE := v_book_list(i);
            v_copies  NUMBER;
        BEGIN
            SELECT AvailableCopies INTO v_copies
            FROM Book
            WHERE BookID = v_book_id;

            IF v_copies > 0 THEN
                INSERT INTO LoanDetail (LoanID, BookID, Status)
                VALUES (v_newLoanId, v_book_id, 'BORROWED');

                UPDATE Book
                SET AvailableCopies = AvailableCopies - 1
                WHERE BookID = v_book_id;

            ELSE
                DBMS_OUTPUT.PUT_LINE('Book ' || v_book_id || ' is not available.');
            END IF;
        END;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Loan created successfully with ID: ' || v_newLoanId);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error during loan operation: ' || SQLERRM);
END;
/



-- !!!!
CREATE OR REPLACE PROCEDURE prc_extend_loan (v_loan_id IN CHAR, v_book_id IN CHAR) IS
    v_current_due_date DATE;
    v_extension_count  NUMBER;
BEGIN
    SELECT ExtensionCount, NVL(ExtendedDueDate, (SELECT DueDate FROM Loan WHERE LoanID = v_loan_id))
    INTO v_extension_count, v_current_due_date
    FROM LoanDetail
    WHERE LoanID = v_loan_id AND BookID = v_book_id;

    IF v_extension_count < 3 THEN
        UPDATE LoanDetail
        SET 
            ExtendedDueDate = v_current_due_date + 7,
            ExtensionCount = v_extension_count + 1
        WHERE LoanID = v_loan_id AND BookID = v_book_id;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Loan extended successfully. New due date: ' || (v_current_due_date + 7));
    ELSE
        DBMS_OUTPUT.PUT_LINE('Extension limit reached for this book.');
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Loan detail not found for the specified Loan ID and Book ID.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/

-- 1. Valid extension (ExtensionCount < 3)
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- Test Case 1: Valid Extension ---');
    prc_extend_loan('LOA0000101', 'BOK0000002');
END;
/

-- 2. Extension limit reached (manually ensure ExtensionCount = 3 for this book before running)
BEGIN
UPDATE LoanDetail
SET ExtensionCount = 3
WHERE LoanID = 'LOA0000101' AND BookID = 'BOK0000002';

    DBMS_OUTPUT.PUT_LINE('--- Test Case 2: Extension Limit Reached ---');
    prc_extend_loan('LOA0000101', 'BOK0000002');
END;
/

-- 3. Loan detail not found (Invalid Loan ID or Book ID)
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- Test Case 3: Loan Detail Not Found ---');
    prc_extend_loan('LOA9999999', 'LOA9999999');
END;
/

-- 4. (Optional) Unexpected error — Example: NULL as Loan ID (forces error if your table constraints disallow it)
BEGIN
    DBMS_OUTPUT.PUT_LINE('--- Test Case 4: Unexpected Error (NULL input) ---');
    prc_extend_loan(NULL, 'BOK0000003');
END;
/
