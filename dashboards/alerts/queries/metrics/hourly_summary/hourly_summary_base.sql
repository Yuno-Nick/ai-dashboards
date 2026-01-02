-- ==============================================================================
-- NORMAL BASE: Common Information - Hourly Call Counts (Last 7 days)
-- ==============================================================================

SELECT
    created_hour AS eval_hour,
    organization_name,
    country,
    COUNT(*) AS total_calls,
    SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
    SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS good_calls,
    SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
    SUM(CASE WHEN call_classification = 'failed' THEN 1 ELSE 0 END) AS failed_calls,
    SUM(CASE WHEN call_classification = 'voicemail' THEN 1 ELSE 0 END) AS voicemail_calls

FROM ai_calls_detail
WHERE 
    created_date >= CURRENT_DATE() - INTERVAL 7 DAY
    AND created_hour < DATE_TRUNC('hour', CURRENT_TIMESTAMP())
    [[AND {{organization_name}}]]
    [[AND {{country}}]]
GROUP BY created_hour, organization_name, country
ORDER BY created_hour DESC, organization_name, country 