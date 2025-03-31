/*
Bad practices and problems in this procedure:

Lack of error handling: No exception handlers are used, which can cause the procedure to fail uncontrollably in the event of errors.

Lack of critical validations: No verification is made of whether the policy is active or whether the claim amount exceeds the insured amount, which can lead to improper claim approvals.

Poor fraud logic: Fraud detection is based solely on the number of previous claims without considering the time period or the claim amount, which can generate false positives or negatives.

Updates and records without appropriate conditions: The claim status is updated, and payments and fraud records are inserted without checking the necessary conditions, which can result in data inconsistencies.

Lack of transactions: No START TRANSACTION, COMMIT, or ROLLBACK are used, which can leave the database in an inconsistent state if an error occurs during execution.

Non-descriptive variable names: Some variables have names that don't clearly reflect their purpose, making the code difficult to understand.

Inefficient resource usage: Indexes aren't considered in queries, which can impact performance in databases with large volumes of data.
*/

DELIMITER $$

CREATE PROCEDURE process_claim_bad(p_claim_id INT)
BEGIN 
DECLARE v_customer_id INT; 
DECLARE v_policy_id INT; 
DECLARE v_claim_amount DECIMAL(10,2); 
DECLARE v_policy_amount DECIMAL(10,2); 
DECLARE v_policy_status VARCHAR(50); 
DECLARE v_existing_claims INT; 
DECLARE v_fraud_flag BOOLEAN; 
DECLARE v_status VARCHAR(20); 
DECLARE v_payment_id INT; 

-- Get claim details without error handling
SELECT customer_id, policy_id, claim_amount
INTO v_customer_id, v_policy_id, v_claim_amount
FROM claims
WHERE claim_id = p_claim_id;

-- Get policy details without checking if the policy is active
SELECT insured_amount, policy_status
INTO v_policy_amount, v_policy_status
FROM policies
WHERE policy_id = v_policy_id;

-- Do not validate if the policy is active
-- Do not validate if the claim amount exceeds the insured amount

-- Count the customer's previous claims regardless of the time period
SELECT COUNT(*)
INTO v_existing_claims
FROM claims
WHERE customer_id = v_customer_id;

-- Flag as possible fraud without clear logic 
IF v_existing_claims > 3 THEN 
SET v_fraud_flag = TRUE; 
ELSE 
SET v_fraud_flag = FALSE; 
END IF; 

-- Update claim status without verifying conditions 
UPDATE claims 
SET status = 'Processed', resolution_date = NOW() 
WHERE claim_id = p_claim_id; 

-- Insert payment without checking claim status 
INSERT INTO payments (claim_id, customer_id, policy_id, payment_date, amount_payment) 
VALUES (p_claim_id, v_customer_id, v_policy_id, NOW(), v_claim_amount); 

-- Insert into fraud table without checking fraud flag 
INSERT INTO fraud_cases (customer_id, claim_id, fraud_type, detection_date) 
VALUES (v_customer_id, p_claim_id, 'Possible Fraud', NOW()); 

-- Do not handle transactions or errors
END $$

DELIMITER ;

/*
Meaningful Names:

Procedure: The name process_claim clearly indicates that the procedure is responsible for processing claims.

Variables and Parameters: Descriptive names such as v_customer_id, v_policy_id, and v_claim_amount are used, making the code easier to understand.

Internal Documentation:

Explanatory comments have been added before key blocks to describe their function, improving code readability and maintainability.

Appropriate Transactions:

START TRANSACTION is used at the start to group all operations into a single transaction.

COMMIT and ROLLBACK are implemented to commit or rollback changes based on the results of the operations, ensuring data integrity.

Specific Error Handling:

An exit handler is declared for SQLEXCEPTION that captures any errors during execution.

In the event of an error, a ROLLBACK is executed and a signal with a custom message is generated, making it easier to identify and Troubleshooting.

Using Indexes:

Although not explicitly shown in the procedure, columns used in WHERE clauses (such as claim_id, customer_id, policy_id) are assumed to be indexed to improve query performance.

Avoiding Dynamic SQL:

The procedure uses static SQL statements, which improves security and performance by preventing SQL injections and reducing compilation overhead.
*/

DELIMITER //

CREATE PROCEDURE process_claim( 
IN p_claim_id INT
)
BEGIN 
-- Variable declaration 
DECLARE v_customer_id INT; 
DECLARE v_policy_id INT; 
DECLARE v_claim_amount DECIMAL(10,2); 
DECLARE v_policy_amount DECIMAL(10,2); 
DECLARE v_policy_status VARCHAR(50); 
DECLARE v_existing_claims INT DEFAULT 0; 
DECLARE v_fraud_flag BOOLEAN DEFAULT FALSE; 
DECLARE v_status VARCHAR(20); 
DECLARE exit handler for sqlexception 
BEGIN 
-- Error handling: undo transaction and log the error 
ROLLBACK; 
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error processing claim'; 
END; 

-- Start transaction 
START TRANSACTION; 

-- Get claim details 
SELECT customer_id, policy_id, claim_amount 
INTO v_customer_id, v_policy_id, v_claim_amount 
FROM claims 
WHERE claim_id = p_claim_id; 

-- Get policy details 
SELECT insured_amount, policy_status 
INTO v_policy_amount, v_policy_status 
FROM policies 
WHERE policy_id = v_policy_id; 

-- Validate if the policy is active 
IF v_policy_status <> 'Active' THEN 
SET v_status = 'Rejected'; 
ELSE
-- Validate if the claimed amount exceeds the insured amount
IF v_claim_amount > v_policy_amount THEN
SET v_status = 'Rejected';
ELSE
SET v_status = 'Approved';
END IF;
END IF;

-- Count the customer's previous claims in the last year
SELECT COUNT(*)
INTO v_existing_claims
FROM claims
WHERE customer_id = v_customer_id
AND claim_date >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR);

-- Flag as possible fraud if there are more than 3 claims in the last year or the claimed amount is suspicious
IF v_existing_claims > 3 OR v_claim_amount > v_policy_amount * 0.8 THEN
SET v_fraud_flag = TRUE;
END IF;

-- Update claim status 
UPDATE claims 
SET status = v_status, resolution_date = NOW() 
WHERE claim_id = p_claim_id; 

-- If the claim was approved, generate a payment 
IF v_status = 'Approved' THEN 
INSERT INTO payments (claim_id, customer_id, policy_id, payment_date, amount_payment) 
VALUES (p_claim_id, v_customer_id, v_policy_id, NOW(), v_claim_amount); 
END IF; 

-- If possible fraud was detected, record in the fraud table 
IF v_fraud_flag THEN 
INSERT INTO fraud_cases (customer_id, claim_id, fraud_type, detection_date) 
VALUES (v_customer_id, p_claim_id, 'Possible Fraud', NOW()); 
END IF; 

-- Confirm transaction 
COMMIT;
END //

DELIMITER ;