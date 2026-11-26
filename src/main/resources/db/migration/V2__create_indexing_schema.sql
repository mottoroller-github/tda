-- V2__create_indexing_schema.sql
-- Tech Debt Assistant (TDA)
-- Indexing jobs and semantic code chunks.
--
-- Requires a PostgreSQL installation with the pgvector extension available.
-- Embeddings use 1536 dimensions; keep this aligned with the configured embedding model.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE indexing_job (
    id                  UUID PRIMARY KEY,
    repository_id       UUID NOT NULL,
    revision_id         UUID NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'QUEUED',
    attempt_count       INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at          TIMESTAMPTZ,
    finished_at         TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    error_code          VARCHAR(100),
    error_message       TEXT,

    CONSTRAINT fk_indexing_job_revision
        FOREIGN KEY (repository_id, revision_id)
        REFERENCES repository_revision (repository_id, id)
        ON DELETE CASCADE,
    -- Enables code_chunk to enforce that its producing job belongs to the same revision.
    CONSTRAINT uq_indexing_job_revision_id
        UNIQUE (revision_id, id),
    CONSTRAINT ck_indexing_job_status
        CHECK (status IN ('QUEUED', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    CONSTRAINT ck_indexing_job_attempt_count
        CHECK (attempt_count >= 0),
    CONSTRAINT ck_indexing_job_timestamps
        CHECK (
			(started_at IS NULL OR started_at >= created_at)
			AND (
				finished_at IS NULL
				OR finished_at >= COALESCE(started_at, created_at)
			)
			AND (
				(status IN ('QUEUED', 'RUNNING') AND finished_at IS NULL)
				OR
				(status IN ('COMPLETED', 'FAILED') AND started_at IS NOT NULL AND finished_at IS NOT NULL)
				OR
				(status = 'CANCELLED' AND finished_at IS NOT NULL)
			)
			AND (status <> 'RUNNING' OR started_at IS NOT NULL)
		),
    CONSTRAINT ck_indexing_job_error_message
        CHECK (error_message IS NULL OR length(btrim(error_message)) > 0)
);

COMMENT ON TABLE indexing_job IS
    'A persisted attempt to index one exact repository revision. Application logic should publish a new index only after successful completion.';

CREATE INDEX ix_indexing_job_status_created
    ON indexing_job (status, created_at);

CREATE INDEX ix_indexing_job_repository_revision
    ON indexing_job (repository_id, revision_id, created_at DESC);
	
CREATE INDEX ix_indexing_job_completed_revision
    ON indexing_job (revision_id, finished_at DESC)
    WHERE status = 'COMPLETED';

CREATE TABLE code_chunk (
    id                  UUID PRIMARY KEY,
    revision_id         UUID NOT NULL,
    file_id             UUID NOT NULL,
    indexing_job_id     UUID NOT NULL,
    chunk_index         INTEGER NOT NULL,
    start_line          INTEGER NOT NULL,
    end_line            INTEGER NOT NULL,
    chunk_hash          VARCHAR(64) NOT NULL,
    content             TEXT NOT NULL,
    embedding_model     VARCHAR(150),
    embedding            VECTOR(1536),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_code_chunk_file
        FOREIGN KEY (revision_id, file_id)
        REFERENCES repository_file (revision_id, id)
        ON DELETE CASCADE,
    CONSTRAINT fk_code_chunk_indexing_job
        FOREIGN KEY (revision_id, indexing_job_id)
        REFERENCES indexing_job (revision_id, id)
        ON DELETE CASCADE,
    CONSTRAINT uq_code_chunk_file_index
        UNIQUE (file_id, indexing_job_id, chunk_index),
    CONSTRAINT ck_code_chunk_index_nonnegative
        CHECK (chunk_index >= 0),
    CONSTRAINT ck_code_chunk_line_range
        CHECK (start_line >= 1 AND end_line >= start_line),
    CONSTRAINT ck_code_chunk_hash
        CHECK (chunk_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_code_chunk_content_not_blank
        CHECK (length(btrim(content)) > 0),
    CONSTRAINT ck_code_chunk_embedding_model
        CHECK (
			(embedding IS NULL AND embedding_model IS NULL)
			OR
			(
				embedding IS NOT NULL
				AND embedding_model IS NOT NULL
				AND length(btrim(embedding_model)) > 0
			)
		)
);

COMMENT ON TABLE code_chunk IS
    'A source-code or text chunk associated with one file snapshot and the indexing job that produced it.';
COMMENT ON COLUMN code_chunk.embedding IS
    '1536-dimensional embedding; nullable until embedding generation succeeds.';
COMMENT ON COLUMN code_chunk.chunk_hash IS
    'SHA-256 hash of normalized chunk content, useful for incremental indexing and duplicate detection.';

CREATE INDEX ix_code_chunk_revision_file
    ON code_chunk (revision_id, file_id);

CREATE INDEX ix_code_chunk_hash
    ON code_chunk (chunk_hash);

CREATE INDEX ix_code_chunk_embedding_model
    ON code_chunk (embedding_model)
    WHERE embedding_model IS NOT NULL;

-- HNSW supports approximate nearest-neighbor search with cosine distance.
-- A partial index avoids indexing chunks that have not yet received embeddings.
CREATE INDEX ix_code_chunk_embedding_hnsw
    ON code_chunk
    USING hnsw (embedding vector_cosine_ops)
    WHERE embedding IS NOT NULL;
