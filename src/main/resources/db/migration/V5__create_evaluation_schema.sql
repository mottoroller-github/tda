-- V5__create_evaluation_schema.sql
-- Tech Debt Assistant (TDA)

CREATE TABLE evaluation_case (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    evaluation_type VARCHAR(50) NOT NULL,
    input_data JSONB NOT NULL,
    expected_output JSONB,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_evaluation_case_name CHECK (length(btrim(name)) > 0),
    CONSTRAINT ck_evaluation_case_type CHECK (length(btrim(evaluation_type)) > 0),
    CONSTRAINT uq_evaluation_case_name_type UNIQUE (name, evaluation_type)
);

COMMENT ON TABLE evaluation_case IS
    'Reusable test case for evaluating TDA indexing, review, or documentation behavior.';

CREATE TABLE evaluation_run (
    id UUID PRIMARY KEY,
    name VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'QUEUED',
    system_version VARCHAR(100),
    model_provider VARCHAR(100),
    model_name VARCHAR(150),
    prompt_version VARCHAR(100),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    error_message TEXT,

    CONSTRAINT ck_evaluation_run_status
        CHECK (status IN ('QUEUED', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    CONSTRAINT ck_evaluation_run_timestamps
        CHECK (
			(started_at IS NULL OR started_at >= created_at)
			AND (
				completed_at IS NULL
				OR completed_at >= COALESCE(started_at, created_at)
			)
			AND (
				(status IN ('QUEUED', 'RUNNING') AND completed_at IS NULL)
				OR
				(status IN ('COMPLETED', 'FAILED') AND started_at IS NOT NULL AND completed_at IS NOT NULL)
				OR
				(status = 'CANCELLED' AND completed_at IS NOT NULL)
			)
			AND (status <> 'RUNNING' OR started_at IS NOT NULL)
		),
    CONSTRAINT ck_evaluation_run_name
        CHECK (name IS NULL OR length(btrim(name)) > 0),
	CONSTRAINT ck_evaluation_run_error_message
		CHECK (error_message IS NULL OR length(btrim(error_message)) > 0)
);

COMMENT ON TABLE evaluation_run IS
    'One execution of an evaluation suite against a particular TDA/model/prompt configuration.';

CREATE INDEX ix_evaluation_run_created ON evaluation_run (created_at DESC);
CREATE INDEX ix_evaluation_run_status_created ON evaluation_run (status, created_at);

CREATE TABLE evaluation_result (
    id UUID PRIMARY KEY,
    evaluation_run_id UUID NOT NULL,
    evaluation_case_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    actual_output JSONB,
    score NUMERIC(8,5),
    metrics JSONB,
    duration_ms BIGINT,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,

    CONSTRAINT fk_evaluation_result_run
        FOREIGN KEY (evaluation_run_id)
        REFERENCES evaluation_run (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_evaluation_result_case
        FOREIGN KEY (evaluation_case_id)
        REFERENCES evaluation_case (id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_evaluation_result_run_case
        UNIQUE (evaluation_run_id, evaluation_case_id),
    CONSTRAINT ck_evaluation_result_status
        CHECK (status IN ('PENDING', 'RUNNING', 'PASSED', 'FAILED', 'ERROR', 'SKIPPED')),
    CONSTRAINT ck_evaluation_result_score
        CHECK (score IS NULL OR (score >= 0 AND score <= 1)),
    CONSTRAINT ck_evaluation_result_duration
        CHECK (duration_ms IS NULL OR duration_ms >= 0),
    CONSTRAINT ck_evaluation_result_completed
        CHECK (
			(completed_at IS NULL OR completed_at >= created_at)
			AND (
				(status IN ('PENDING', 'RUNNING') AND completed_at IS NULL)
				OR
				(status IN ('PASSED', 'FAILED', 'ERROR', 'SKIPPED') AND completed_at IS NOT NULL)
			)
		),
	CONSTRAINT ck_evaluation_result_error_message
		CHECK (error_message IS NULL OR length(btrim(error_message)) > 0)
);

COMMENT ON TABLE evaluation_result IS
    'Outcome and optional metrics for one evaluation case within one evaluation run. Scores use the normalized 0..1 range.';

CREATE INDEX ix_evaluation_result_run_status
    ON evaluation_result (evaluation_run_id, status);
CREATE INDEX ix_evaluation_result_case
    ON evaluation_result (evaluation_case_id);
