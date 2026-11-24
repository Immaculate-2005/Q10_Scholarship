DROP SCHEMA IF EXISTS q10_scholarship CASCADE;
CREATE SCHEMA q10_scholarship;
SET search_path TO q10_scholarship, public;

CREATE TABLE students(
 student_id SERIAL PRIMARY KEY,student_number VARCHAR(30) UNIQUE NOT NULL,full_name VARCHAR(120) NOT NULL
);
CREATE TABLE applications(
 application_id SERIAL PRIMARY KEY,student_id INTEGER NOT NULL REFERENCES students(student_id),
 age_at_application INTEGER NOT NULL CHECK(age_at_application>0),
 monthly_income NUMERIC(12,2) NOT NULL CHECK(monthly_income>=0),
 average_mark NUMERIC(5,2) NOT NULL CHECK(average_mark BETWEEN 0 AND 100),
 submitted_on DATE NOT NULL,
 status VARCHAR(10) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','APPROVED','REJECTED'))
);
CREATE TABLE decision_audit(
 audit_id SERIAL PRIMARY KEY,application_id INTEGER NOT NULL REFERENCES applications(application_id),
 old_status VARCHAR(10),new_status VARCHAR(10),changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INTEGER,p_income NUMERIC,p_mark NUMERIC)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
 IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL OR p_age<=0 OR p_income<0 OR p_mark<0 OR p_mark>100 THEN
  RAISE EXCEPTION 'Invalid eligibility input';
 END IF;
 RETURN p_age BETWEEN 18 AND 25 AND p_income<=3000 AND p_mark>=70;
END; $$;

CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id INTEGER)
LANGUAGE plpgsql AS $$
DECLARE r RECORD; v_status VARCHAR(10);
BEGIN
 SELECT age_at_application,monthly_income,average_mark,status INTO r
 FROM applications WHERE application_id=p_application_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown application'; END IF;
 IF r.status<>'PENDING' THEN RAISE EXCEPTION 'Application has already been assessed'; END IF;
 IF fn_scholarship_eligible(r.age_at_application,r.monthly_income,r.average_mark) THEN
  v_status:='APPROVED';
 ELSE
  v_status:='REJECTED';
 END IF;
 UPDATE applications SET status=v_status WHERE application_id=p_application_id;
END; $$;

CREATE OR REPLACE FUNCTION trg_fn_decision_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.status IS DISTINCT FROM NEW.status THEN
  INSERT INTO decision_audit(application_id,old_status,new_status)
  VALUES(NEW.application_id,OLD.status,NEW.status);
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER trg_decision_audit AFTER UPDATE ON applications
FOR EACH ROW EXECUTE FUNCTION trg_fn_decision_audit();

INSERT INTO students(student_number,full_name) VALUES
('ST001','Alice Banda'),('ST002','Brian Phiri'),('ST003','Chanda Zulu');
INSERT INTO applications(student_id,age_at_application,monthly_income,average_mark,submitted_on,status) VALUES
(1,18,3000,70,CURRENT_DATE,'PENDING'),
(1,25,2500,85,CURRENT_DATE,'PENDING'),
(2,17,2000,90,CURRENT_DATE,'PENDING'),
(2,22,3500,80,CURRENT_DATE,'PENDING'),
(3,24,2800,69,CURRENT_DATE,'PENDING'),
(3,26,3000,75,CURRENT_DATE,'PENDING');

CREATE OR REPLACE PROCEDURE pr_assess_pending()
LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
 FOR r IN SELECT application_id FROM applications WHERE status='PENDING' LOOP
  CALL pr_assess_application(r.application_id);
 END LOOP;
END; $$;

CALL pr_assess_pending();

CREATE OR REPLACE VIEW v_approved_applicants AS
SELECT s.student_number,s.full_name,a.average_mark,a.status
FROM applications a JOIN students s ON s.student_id=a.student_id
WHERE a.status='APPROVED';

CREATE INDEX idx_applications_status_submitted ON applications(status,submitted_on);
EXPLAIN SELECT * FROM applications WHERE status='PENDING'
AND submitted_on BETWEEN CURRENT_DATE-30 AND CURRENT_DATE;

CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('q10-assess-pending','0 8 * * 1',
 'CALL q10_scholarship.pr_assess_pending()');

SELECT * FROM v_approved_applicants;
SELECT * FROM decision_audit;
