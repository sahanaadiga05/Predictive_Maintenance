CREATE DATABASE pred_maintenance;
use pred_maintenance;

select count(*) 
from machine_data;

select *
from machine_data
limit 5;

-- 1. failure by machine type & region ( Shows which machine type + region combination has the highest operational risk.)
select 
	type,
    region,
    count(*) as total_machines,
    sum(target) as total_failures,
    round(sum(target)*100.0 / count(*), 2) as failure_rate_pct,
    round(avg(torque),2) as avg_torque,
    round(avg(tool_wear),2) as avg_tool_wear
from machine_data
group by type, region
order by failure_rate_pct desc;
    
-- 2. LAG/LEAD: time btwn failures per machine type (This is your LAG/LEAD window function — calculates the tool wear gap between consecutive failures, showing how quickly machines degrade between events.)
WITH failure_events AS (
    SELECT
        product_id,
        type,
        region,
        failure_type,
        tool_wear,
        torque,
        ROW_NUMBER() OVER (PARTITION BY type ORDER BY tool_wear) AS event_seq
    FROM machine_data
    WHERE target = 1
),
with_lag AS (
    SELECT
        product_id,
        type,
        region,
        failure_type,
        tool_wear                                                           AS current_wear,
        LAG(tool_wear)  OVER (PARTITION BY type ORDER BY tool_wear)        AS prev_failure_wear,
        LEAD(tool_wear) OVER (PARTITION BY type ORDER BY tool_wear)        AS next_failure_wear,
        event_seq
    FROM failure_events
)
SELECT
    product_id,
    type,
    region,
    failure_type,
    current_wear,
    prev_failure_wear,
    next_failure_wear,
    ROUND(current_wear - prev_failure_wear, 2)  AS wear_gap_since_last_failure,
    ROUND(next_failure_wear - current_wear, 2)  AS wear_gap_to_next_failure
FROM with_lag
WHERE prev_failure_wear IS NOT NULL
ORDER BY type, current_wear;

-- 3. self-join: machines that failed multiple times (reoeat offenders)
select 
	a.product_id,
    a.type,
    a.region,
    a.failure_type as first_failure,
    b.failure_type as second_failure,
    a.tool_wear  as first_failure_wear,
    b.tool_wear as second_failure_wear,
    round(b.tool_wear - a.tool_wear, 2) as wear_between_failures
from machine_data a
join machine_data b
	on a.product_id = b.product_id
    and a.tool_wear < b.tool_wear
    and a.target= 1
    and b.target = 1
    and a.failure_type != 'No Failure'
    and b.failure_type != 'No Failure'
order by a.product_id, a.tool_wear;


SELECT
    a.type                                      AS machine_type,
    a.region,
    a.failure_type                              AS failure_type_A,
    b.failure_type                              AS failure_type_B,
    COUNT(*)                                    AS co_occurrence_count,
    ROUND(AVG(a.torque), 2)                     AS avg_torque_A,
    ROUND(AVG(b.torque), 2)                     AS avg_torque_B,
    ROUND(AVG(a.tool_wear), 2)                  AS avg_wear_A,
    ROUND(AVG(b.tool_wear), 2)                  AS avg_wear_B
FROM machine_data a
JOIN machine_data b
    ON  a.type          = b.type
    AND a.region        = b.region
    AND a.failure_type  != b.failure_type
    AND a.target        = 1
    AND b.target        = 1
    AND a.failure_type  != 'No Failure'
    AND b.failure_type  != 'No Failure'
    AND a.failure_type  < b.failure_type
GROUP BY a.type, a.region, a.failure_type, b.failure_type
ORDER BY co_occurrence_count DESC;

-- 4.regional risk ranking with window fuctions ( These are machines that haven't failed yet but show high-stress sensor readings — your "next 30 days at risk" list for Power BI.)
SELECT *
from(
select
    region,
    type,
    failure_type,
    COUNT(*)                                                        AS failure_count,
    ROUND(AVG(torque), 2)                                           AS avg_torque,
    ROUND(AVG(tool_wear), 2)                                        AS avg_tool_wear,
    RANK()     OVER (PARTITION BY region ORDER BY COUNT(*) DESC)    AS rank_within_region,
    DENSE_RANK() OVER (ORDER BY COUNT(*) DESC)                      AS global_rank
FROM machine_data
WHERE target = 1
  AND failure_type != 'No Failure'
GROUP BY region, type, failure_type
) ranked_results
ORDER BY global_rank;


-- 5. 30-day at risk machines(high wear, no failure yet)
select
	product_id,
    type,
    region,
    round(air_temp_c, 2) as air_temp_c,
    round(process_temp_c, 2) as process_temp_c,
    round(torque,2) as torque, tool_wear,
    round(tool_wear_ratio, 4) as tool_wear_ratio,
    round(power_watts,2) as power_watts,
    target,
    failure_type,
    case
		when tool_wear_ratio > 0.85 then 'Critical'
        when tool_wear_ratio > 0.65 and torque > 45 then 'High'
        when tool_wear_ratio > 0.45 or torque > 40 then 'Medium'
        else 'Low'
        
	end as risk_flag
from machine_data
where target =0
and (tool_wear_ratio > 0.45 or torque > 40)
order by tool_wear_ratio desc, torque desc
limit 500;





