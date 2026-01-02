-- ==============================================================================
-- CURRENT BASE: Common Information - Today's Call Counts
-- ==============================================================================

WITH current_time_parts AS (
    SELECT 
        EXTRACT(HOUR FROM CURRENT_TIMESTAMP()) AS current_hour,
        EXTRACT(MINUTE FROM CURRENT_TIMESTAMP()) AS current_minute
)

SELECT
    CURRENT_TIMESTAMP() AS evaluated_at,
    organization_name,
    country,
    COUNT(*) AS current_total_calls,
    SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS current_completed_calls,
    SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS current_good_calls,
    SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS current_short_calls,
    SUM(CASE WHEN call_classification = 'failed' THEN 1 ELSE 0 END) AS current_failed_calls,
    SUM(CASE WHEN call_classification = 'voicemail' THEN 1 ELSE 0 END) AS current_voicemail_calls

FROM ai_calls_detail, current_time_parts ctp
WHERE 
    created_date = CURRENT_DATE()
    AND (
        EXTRACT(HOUR FROM created_at) < ctp.current_hour
        OR (
            EXTRACT(HOUR FROM created_at) = ctp.current_hour
            AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute
        )
    )
    [[AND {{organization_name}}]]
    [[AND {{country}}]]
GROUP BY organization_name, country
ORDER BY organization_name, country