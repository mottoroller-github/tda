-- V4__create_documentation_schema.sql
-- Tech Debt Assistant (TDA)

CREATE TABLE documentation_task (
    id UUID PRIMARY KEY,
    repository_id UUID NOT NULL,
    revision_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'QUEUED',
    scope VARCHAR(30) NOT NULL DEFAULT 'WHOLE_REPOSITORY',
    documentation_version VARCHAR(100),
    model_provider VARCHAR(100),
    model_name VARCHAR(150),
    prompt_version VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    error_code VARCHAR(100),
    error_message TEXT,

    CONSTRAINT fk_documentation_task_revision
        FOREIGN KEY (repository_id, revision_id)
        REFERENCES repository_revision (repository_id, id)
        ON DELETE CASCADE,
    CONSTRAINT uq_documentation_task_revision_id UNIQUE (revision_id, id),
    CONSTRAINT ck_documentation_task_status
        CHECK (status IN ('QUEUED', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    CONSTRAINT ck_documentation_task_scope
        CHECK (scope IN ('WHOLE_REPOSITORY', 'PACKAGE', 'FILE')),
    CONSTRAINT ck_documentation_task_timestamps
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
    CONSTRAINT ck_documentation_task_error_message
        CHECK (error_message IS NULL OR length(btrim(error_message)) > 0)
);

COMMENT ON TABLE documentation_task IS
    'A persisted documentation generation task against one exact repository revision.';

CREATE INDEX ix_documentation_task_revision_created
    ON documentation_task (revision_id, created_at DESC);
CREATE INDEX ix_documentation_task_status_created
    ON documentation_task (status, created_at);

CREATE TABLE documentation_result (
    id UUID PRIMARY KEY,
    documentation_task_id UUID NOT NULL,
    revision_id UUID NOT NULL,
    document_type VARCHAR(50) NOT NULL,
    title VARCHAR(500) NOT NULL,
    relative_path TEXT,
    content_format VARCHAR(20) NOT NULL DEFAULT 'MARKDOWN',
    content TEXT NOT NULL,
    content_hash VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_documentation_result_task_revision
        FOREIGN KEY (revision_id, documentation_task_id)
        REFERENCES documentation_task (revision_id, id)
        ON DELETE CASCADE,
    CONSTRAINT ck_documentation_result_type
        CHECK (length(btrim(document_type)) > 0),
    CONSTRAINT ck_documentation_result_title
        CHECK (length(btrim(title)) > 0),
    CONSTRAINT ck_documentation_result_format
        CHECK (content_format IN ('MARKDOWN', 'TEXT', 'HTML', 'JSON')),
    CONSTRAINT ck_documentation_result_content_not_blank
        CHECK (length(btrim(content)) > 0),
    CONSTRAINT ck_documentation_result_content_hash
        CHECK (content_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_documentation_result_relative_path
        CHECK (
			relative_path IS NULL OR (
				length(btrim(relative_path)) > 0
				AND relative_path !~ '^/'
				AND relative_path !~ '^[A-Za-z]:'
				AND relative_path !~ '(^|/)\.\.(/|$)'
				AND relative_path !~ E'(^|\\\\)\\.\\.(\\\\|$)'
				AND relative_path !~ E'\\\\'
			)
		),
    CONSTRAINT uq_documentation_result_task_path
        UNIQUE (documentation_task_id, relative_path)
);

COMMENT ON TABLE documentation_result IS
    'A generated documentation artifact. Results are immutable outputs of a documentation task.';
COMMENT ON COLUMN documentation_result.relative_path IS
    'Optional repository-relative destination; application code must additionally validate normalized paths.';

CREATE INDEX ix_documentation_result_task
    ON documentation_result (documentation_task_id);
CREATE INDEX ix_documentation_result_revision_type
    ON documentation_result (revision_id, document_type);
