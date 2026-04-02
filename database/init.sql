-- TF05 - Schema do Banco de Dados de Monitoramento

CREATE TABLE IF NOT EXISTS metrics (
    id          SERIAL PRIMARY KEY,
    service     VARCHAR(100) NOT NULL,
    status      VARCHAR(20)  NOT NULL,
    response_time INTEGER DEFAULT 0,
    uptime      NUMERIC(5,2) DEFAULT 0,
    detail      TEXT,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS alerts (
    id          SERIAL PRIMARY KEY,
    service     VARCHAR(100) NOT NULL,
    level       VARCHAR(20)  NOT NULL,
    title       VARCHAR(255) NOT NULL,
    description TEXT,
    resolved    BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS health_history (
    id          SERIAL PRIMARY KEY,
    service     VARCHAR(100) NOT NULL,
    status      VARCHAR(20)  NOT NULL,
    uptime      NUMERIC(5,2) DEFAULT 0,
    avg_response_time INTEGER DEFAULT 0,
    checks_ok   INTEGER DEFAULT 0,
    checks_failed INTEGER DEFAULT 0,
    recorded_at TIMESTAMP DEFAULT NOW()
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_metrics_service ON metrics(service);
CREATE INDEX IF NOT EXISTS idx_metrics_created ON metrics(created_at);
CREATE INDEX IF NOT EXISTS idx_alerts_service ON alerts(service);
CREATE INDEX IF NOT EXISTS idx_alerts_resolved ON alerts(resolved);
CREATE INDEX IF NOT EXISTS idx_history_service ON health_history(service);
CREATE INDEX IF NOT EXISTS idx_history_recorded ON health_history(recorded_at);

-- Dados iniciais de configuração
INSERT INTO alerts (service, level, title, description)
VALUES ('system', 'info', 'Sistema de monitoramento iniciado', 'TF05 - Banco de dados inicializado com sucesso')
ON CONFLICT DO NOTHING;
