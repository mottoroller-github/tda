-- V3__create_review_schema.sql
-- Tech Debt Assistant (TDA)
-- Review sessions and findings pinned to an exact repository revision.

CREATE TABLE review_session (
    id                  UUID PRIMARY KEY,
    repository_id       UUID NOT NULL,
    revision_id         UUID NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'QUEUED',
    scope               VARCHAR(30) NOT NULL DEFAULT 'WHOLE_REPOSITORY',
    analysis_version    VARCHAR(100),
    model_provider      VARCHAR(100),
    model_name          VARCHAR(150),
    prompt_version      VARCHAR(100),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    error_code          VARCHAR(100),
    error_message       TEXT,

    CONSTRAINT fk_review_session_revision
        FOREIGN KEY (repository_id, revision_id)
        REFERENCES repository_revision (repository_id, id)
        ON DELETE CASCADE,
    -- Used by the composite FK on review_finding to enforce revision consistency.
    CONSTRAINT uq_review_session_revision_id
        UNIQUE (revision_id, id),
    CONSTRAINT ck_review_session_status
        CHECK (status IN ('QUEUED', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    CONSTRAINT ck_review_session_scope
        CHECK (scope IN ('WHOLE_REPOSITORY', 'PACKAGE', 'FILE')),
    CONSTRAINT ck_review_session_timestamps
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
    CONSTRAINT ck_review_session_error_message
        CHECK (error_message IS NULL OR length(btrim(error_message)) > 0)
);

COMMENT ON TABLE review_session IS
    'One review execution against a specific immutable repository revision.';
COMMENT ON COLUMN review_session.analysis_version IS
    'Version of TDA analysis logic, for reproducibility.';
COMMENT ON COLUMN review_session.prompt_version IS
    'Version identifier for the prompt/template set used during this review.';

CREATE INDEX ix_review_session_revision_created
    ON review_session (revision_id, created_at DESC);

CREATE INDEX ix_review_session_status_created
    ON review_session (status, created_at);

CREATE TABLE review_finding (
    id                  UUID PRIMARY KEY,
    review_session_id   UUID NOT NULL,
    revision_id         UUID NOT NULL,
    file_id             UUID NOT NULL,
    category            VARCHAR(50) NOT NULL,
    severity            VARCHAR(20) NOT NULL,
    title               VARCHAR(500) NOT NULL,
    description         TEXT NOT NULL,
    recommendation      TEXT,
    rule_id             VARCHAR(200),
    source              VARCHAR(30) NOT NULL DEFAULT 'AI',
    fingerprint         VARCHAR(64) NOT NULL,
    start_line          INTEGER NOT NULL,
    end_line            INTEGER,
    confidence          NUMERIC(4,3),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_review_finding_session_revision
        FOREIGN KEY (revision_id, review_session_id)
        REFERENCES review_session (revision_id, id)
        ON DELETE CASCADE,
    CONSTRAINT fk_review_finding_file_revision
        FOREIGN KEY (revision_id, file_id)
        REFERENCES repository_file (revision_id, id)
        ON DELETE CASCADE,
    CONSTRAINT ck_review_finding_category
        CHECK (length(btrim(category)) > 0),
    CONSTRAINT ck_review_finding_severity
        CHECK (severity IN ('INFO', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    CONSTRAINT ck_review_finding_source
        CHECK (source IN ('STATIC_ANALYSIS', 'AI', 'HYBRID')),
    CONSTRAINT ck_review_finding_title_not_blank
        CHECK (length(btrim(title)) > 0),
    CONSTRAINT ck_review_finding_description_not_blank
        CHECK (length(btrim(description)) > 0),
    CONSTRAINT ck_review_finding_rule_id
        CHECK (rule_id IS NULL OR length(btrim(rule_id)) > 0),
    CONSTRAINT ck_review_finding_fingerprint
        CHECK (fingerprint ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_review_finding_line_range
        CHECK (start_line >= 1 AND (end_line IS NULL OR end_line >= start_line)),
    CONSTRAINT ck_review_finding_confidence
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    CONSTRAINT uq_review_finding_fingerprint
        UNIQUE (review_session_id, fingerprint)
);

COMMENT ON TABLE review_finding IS
    'A review finding whose session and source file are constrained to the same repository revision.';
COMMENT ON COLUMN review_finding.fingerprint IS
    'Stable SHA-256 fingerprint for deduplicating equivalent findings within one review session.';
COMMENT ON COLUMN review_finding.source IS
    'Origin of the finding: static analysis, AI analysis, or a combined result.';

CREATE INDEX ix_review_finding_session_severity
    ON review_finding (review_session_id, severity);
	
CREATE INDEX ix_review_finding_session_category
    ON review_finding (review_session_id, category);

CREATE INDEX ix_review_finding_revision_file_lines
    ON review_finding (revision_id, file_id, start_line);

CREATE INDEX ix_review_finding_category
    ON review_finding (category);
