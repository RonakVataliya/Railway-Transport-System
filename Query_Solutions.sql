SET SEARCH_PATH TO RTDS_DB;

-- 1) Just pulling all trains from Delhi to Mumbai in this time range with their route and type.
SELECT 
    t.train_id,
    t.train_name,
    t.train_type,
    r.route_name,
    sch.starting_ts,
    sch.ending_ts,
    src.station_name AS source_station,
    dst.station_name AS destination_station
FROM schedule sch
JOIN train t       ON sch.train_id       = t.train_id
JOIN route r       ON t.route_id         = r.route_id
JOIN station src   ON sch.source_station_id      = src.station_id
JOIN station dst   ON sch.destination_station_id = dst.station_id
WHERE src.station_id = 'ST001'  -- New Delhi Railway Station
  AND dst.station_id = 'ST004'  -- Mumbai Central
  AND sch.starting_ts BETWEEN '2026-04-15 00:00:00' 
                          AND '2026-04-16 23:59:59'
ORDER BY sch.starting_ts;

-- 2) Detailed PNR lookup so user can see journey, passenger, fare and trip status in one shot.
SELECT 
    tk.pnr,
    ru.name  AS passenger_name,
    ru.email,
    ru.phone,
    tr.train_name,
    tr.train_type,
    s_src.station_name  AS boarding_station,
    s_src.city          AS from_city,
    s_dst.station_name  AS destination_station,
    s_dst.city          AS to_city,
    sch.starting_ts     AS journey_start,
    sch.ending_ts       AS journey_end,
    ((EXTRACT(EPOCH FROM (sch.ending_ts - sch.starting_ts)) / 3600))::NUMERIC(5,2) AS journey_hours,
    tk.passenger_count,
    p.amount            AS ticket_fare,
    p.method            AS payment_method,
    p.payment_time,
    CASE 
        WHEN sch.starting_ts > CURRENT_TIMESTAMP THEN 'Upcoming'
        WHEN sch.ending_ts  < CURRENT_TIMESTAMP THEN 'Completed'
        ELSE 'In Progress'
    END AS trip_status
FROM tickets tk
JOIN registered_user ru 
    ON tk.user_id = ru.user_id
JOIN payment p
    ON tk.transaction_id = p.transaction_id
JOIN schedule sch
    ON tk.schedule_train_id = sch.train_id
   AND tk.schedule_starting_ts = sch.starting_ts
JOIN train tr
    ON tr.train_id = sch.train_id
JOIN station s_src
    ON tk.boarding_station = s_src.station_id
JOIN station s_dst
    ON tk.destination_station = s_dst.station_id
WHERE tk.pnr = 'PNR15001';


-- 3) Full booking transaction demo where we pay, create ticket and add passengers in a single go.
BEGIN;

INSERT INTO payment (transaction_id, amount, method)
VALUES ('TXN91002', 4650.00, 'UPI');

INSERT INTO tickets (
    pnr,
    user_id,
    transaction_id,
    boarding_station,
    destination_station,
    schedule_train_id,
    schedule_starting_ts,
    passenger_count
)
VALUES (
    'PNR19102',
    'U002',
    'TXN91002',
    'ST001',   -- New Delhi
    'ST004',   -- Mumbai Central
    'TR001',
    '2026-04-21 16:30:00',
    2
);

INSERT INTO passenger (
    passenger_id,
    pnr,
    train_id,
    coach_code,
    seat_number,
    name,
    gender,
    dob,
    berth_pref
)
VALUES
    ('P19002A', 'PNR19102', 'TR001', 'A1', '3', 'Sample Person 1', 'Male',   '1998-01-01', 'Lower'),
    ('P19002B', 'PNR19102', 'TR001', 'A1', '2', 'Sample Person 2', 'Female', '1997-03-15', 'Upper');

COMMIT;

-- 4) Simple insert to log a ticket refund with reason and how much money was returned.
INSERT INTO ticket_refund (
    refund_id,
    pnr,
    reason_code,
    refund_amount
)
VALUES (
    'RF19002',
    'PNR19002',
    'USER_CANCEL',
    4000.00
);

-- 5) Checking how many seats are free in each coach for a given train schedule with dynamic pricing.
WITH seat_occupancy AS (
    SELECT
        p.train_id,
        p.coach_code,
        COUNT(*) AS booked_seats
    FROM passenger p
    JOIN tickets tk
        ON tk.pnr = p.pnr
    WHERE tk.schedule_train_id  = 'TR001'
      AND tk.schedule_starting_ts = '2026-04-21 16:30:00'
    GROUP BY p.train_id, p.coach_code
)
SELECT 
    c.train_id,
    t.train_name,
    c.coach_type,
    c.coach_code,
    c.total_seats,
    COALESCE(so.booked_seats, 0) AS booked_seats,
    c.total_seats - COALESCE(so.booked_seats, 0) AS available_seats,
    t.base_fare,
    tc.class_name,
    tc.fare_multiplier,
    (t.base_fare * tc.fare_multiplier * c.fare_multiplier)::NUMERIC(10,2) AS price_per_seat
FROM coach c
JOIN train t       ON t.train_id = c.train_id
JOIN train_class tc ON tc.class_id = t.class_id
LEFT JOIN seat_occupancy so
    ON so.train_id = c.train_id
   AND so.coach_code = c.coach_code
WHERE c.train_id = 'TR001'
ORDER BY c.coach_code;

-- 6) User-wise trip history to see all tickets, when they depart and if the journey is past or upcoming.
SELECT
    tk.pnr,
    ru.user_id,
    ru.name       AS user_name,
    tr.train_name,
    bs.station_name AS from_station,
    ds.station_name AS to_station,
    tk.schedule_starting_ts AS departure,
    tk.booking_ts,
    tk.passenger_count,
    CASE
        WHEN tk.schedule_starting_ts > CURRENT_TIMESTAMP THEN 'Upcoming'
        ELSE 'Past'
    END AS trip_status
FROM tickets tk
JOIN registered_user ru 
    ON ru.user_id = tk.user_id
JOIN schedule sch
    ON sch.train_id = tk.schedule_train_id
   AND sch.starting_ts = tk.schedule_starting_ts
JOIN train tr
    ON tr.train_id = sch.train_id
JOIN station bs
    ON bs.station_id = tk.boarding_station
JOIN station ds
    ON ds.station_id = tk.destination_station
WHERE ru.user_id = 'U001'
ORDER BY tk.schedule_starting_ts DESC;

-- 7) Quick profile fetch for a registered user using either their user id or email.
SELECT
    user_id,
    name,
    email,
    dob,
    address,
    phone
FROM registered_user
WHERE user_id = 'U001'
   OR email   = 'baburao.apte@comedy.com';

-- 8) Find upcoming journeys for a particular passenger based on their name and date of birth.
SELECT
    p.pnr,
    p.passenger_id,
    p.name          AS passenger_name,
    p.gender,
    p.dob,
    tk.user_id,
    tr.train_name,
    st_src.station_name AS boarding_station,
    st_dst.station_name AS destination_station,
    tk.schedule_starting_ts AS departure
FROM passenger p
JOIN tickets tk
    ON tk.pnr = p.pnr
JOIN schedule sch
    ON sch.train_id = tk.schedule_train_id
   AND sch.starting_ts = tk.schedule_starting_ts
JOIN train tr
    ON tr.train_id = sch.train_id
JOIN station st_src
    ON st_src.station_id = tk.boarding_station
JOIN station st_dst
    ON st_dst.station_id = tk.destination_station
WHERE p.name = 'Sample Person 1'
  AND p.dob  = DATE '1998-01-01'
  AND tk.schedule_starting_ts >= CURRENT_TIMESTAMP
ORDER BY tk.schedule_starting_ts;

-- 9) From Ahmedabad, figure out nearby stations in same division/zone that still have no direct trains.
WITH ahd AS (
    SELECT
        st.station_id       AS ahd_id,
        st.division_id      AS ahd_division_id,
        d.zone_id           AS ahd_zone_id
    FROM station st
    JOIN division d
        ON d.division_id = st.division_id
    WHERE st.station_name = 'Ahmedabad Junction'
    LIMIT 1
),
same_area_stations AS (
    SELECT
        st.station_id,
        st.station_name,
        st.city,
        st.division_id,
        d.zone_id
    FROM station st
    JOIN division d
        ON d.division_id = st.division_id
    CROSS JOIN ahd
    WHERE st.station_id <> ahd.ahd_id
      AND (
            st.division_id = ahd.ahd_division_id
         OR d.zone_id      = ahd.ahd_zone_id
      )
),
direct_pairs AS (
    SELECT DISTINCT
        sch.destination_station_id AS dest_id
    FROM schedule sch
    JOIN ahd
        ON sch.source_station_id = ahd.ahd_id
)
SELECT
    s.station_id,
    s.station_name,
    s.city
FROM same_area_stations s
LEFT JOIN direct_pairs dp
    ON dp.dest_id = s.station_id
WHERE dp.dest_id IS NULL
ORDER BY s.station_name
LIMIT 5;

-- 10) Stations that only ever act as source and never as destination in any schedule.
SELECT
    s.station_id,
    s.station_name,
    s.city,
    COUNT(*) AS times_as_source
FROM station s
JOIN schedule sch
    ON sch.source_station_id = s.station_id
LEFT JOIN schedule sch2
    ON sch2.destination_station_id = s.station_id
GROUP BY s.station_id, s.station_name, s.city
HAVING COUNT(sch2.destination_station_id) = 0
ORDER BY times_as_source DESC;

-- 11) Route-wise average speed using distance and typical journey time across all schedules.
WITH route_times AS (
    SELECT
        r.route_id,
        r.route_name,
        r.total_distance,
        AVG(
            EXTRACT(EPOCH FROM (sch.ending_ts - sch.starting_ts)) / 3600
        ) AS avg_hours
    FROM route r
    JOIN train t
        ON t.route_id = r.route_id
    JOIN schedule sch
        ON sch.train_id = t.train_id
    GROUP BY r.route_id, r.route_name, r.total_distance
)
SELECT
    route_id,
    route_name,
    total_distance,
    avg_hours,
    CASE
        WHEN avg_hours > 0 THEN
            ROUND(
                (total_distance / avg_hours)::numeric
            , 2)
        ELSE NULL
    END AS avg_speed_kmph
FROM route_times
ORDER BY avg_speed_kmph DESC NULLS LAST;

-- 12) Daily booking vs cancellation stats to see how many tickets got cancelled each day.
WITH daily_booking AS (
    SELECT
        DATE(booking_ts) AS booking_date,
        COUNT(DISTINCT pnr) AS total_bookings
    FROM tickets
    GROUP BY DATE(booking_ts)
),
daily_refund AS (
    SELECT
        refund_date,
        COUNT(DISTINCT pnr) AS cancelled_bookings
    FROM ticket_refund
    GROUP BY refund_date
)
SELECT
    b.booking_date,
    b.total_bookings,
    COALESCE(r.cancelled_bookings, 0) AS cancelled_bookings,
    ROUND(
        COALESCE(r.cancelled_bookings, 0)::NUMERIC /
        NULLIF(b.total_bookings, 0) * 100
    , 2) AS cancellation_rate_percent
FROM daily_booking b
LEFT JOIN daily_refund r
    ON r.refund_date = b.booking_date
ORDER BY b.booking_date DESC;

-- 13) Get all users with the same name so we can see duplicates like multiple "Anil Mehta".
SELECT
    user_id,
    name,
    email,
    dob,
    address,
    phone
FROM registered_user
WHERE name = 'Anil Mehta';

-- 14) Show all passengers grouped by PNR to see who is travelling together on the same ticket.
SELECT 
    tk.pnr, 
    tk.user_id, 
    p.name, 
    p.dob
FROM tickets tk
JOIN passenger p 
    ON tk.pnr = p.pnr
ORDER BY tk.pnr;

-- 15) Find users who cancel a lot of tickets (50 percent or more of their bookings).
WITH user_bookings AS (
    SELECT 
        ru.user_id,
        ru.name,
        ru.email,
        COUNT(DISTINCT tk.pnr)          AS total_bookings,
        COUNT(DISTINCT trf.refund_id)   AS cancelled_bookings,
        ROUND(
            (COUNT(DISTINCT trf.refund_id)::NUMERIC /
             NULLIF(COUNT(DISTINCT tk.pnr), 0)) * 100
        , 2) AS cancellation_rate
    FROM registered_user ru
    LEFT JOIN tickets tk
        ON ru.user_id = tk.user_id
    LEFT JOIN ticket_refund trf
        ON trf.pnr = tk.pnr
    GROUP BY ru.user_id, ru.name, ru.email
)
SELECT 
    user_id,
    name,
    email,
    total_bookings,
    cancelled_bookings,
    cancellation_rate
FROM user_bookings
WHERE cancellation_rate >= 50
ORDER BY cancellation_rate DESC;

-- 16) Detect crazy booking spikes when a user books many tickets in the same one-hour slot.
WITH per_hour AS (
    SELECT
        user_id,
        date_trunc('hour', booking_ts) AS hour_slot,
        COUNT(*) AS bookings_in_hour
    FROM tickets
    GROUP BY user_id, date_trunc('hour', booking_ts)
)
SELECT
    user_id,
    hour_slot,
    bookings_in_hour
FROM per_hour
WHERE bookings_in_hour >= 1
ORDER BY bookings_in_hour DESC, hour_slot;

-- 17) Route-wise delay analysis using live status to see which routes are usually late.
SELECT
    s.route_id,
    r.route_name,
    ROUND(AVG(l.delay_minutes)::NUMERIC, 2) AS avg_delay_minutes,
    COUNT(*) AS reports
FROM live_train_status l
JOIN schedule s
    ON s.train_id    = l.schedule_train_id
   AND s.starting_ts = l.schedule_starting_ts
JOIN route r
    ON r.route_id = s.route_id
GROUP BY s.route_id, r.route_name
ORDER BY avg_delay_minutes DESC;

-- 18) Top five busiest boarding stations based on how many people start their journey there.
SELECT
    st.station_id,
    st.station_name,
    st.city,
    st.is_junction,
    COUNT(*) AS total_boardings,
    SUM(tk.passenger_count) AS total_passengers
FROM station st
JOIN tickets tk
    ON tk.boarding_station = st.station_id
GROUP BY st.station_id, st.station_name, st.city, st.is_junction
ORDER BY total_boardings DESC
LIMIT 5;

-- 19) All stations in a given city along with whether they are junctions and which division/zone they belong to.
SELECT
    st.station_id,
    st.station_name,
    CASE WHEN st.is_junction THEN 'Junction' ELSE 'Regular' END AS station_type,
    d.division_name,
    z.zone_name
FROM station st
JOIN division d
    ON d.division_id = st.division_id
JOIN zone z
    ON z.zone_id = d.zone_id
WHERE st.city = 'Mumbai'
ORDER BY st.is_junction DESC, st.station_name;

-- 20) Coach composition summary per train to see how many coaches and seats exist for each coach type.
SELECT
    c.train_id,
    t.train_name,
    c.coach_type,
    COUNT(*)           AS num_coaches,
    SUM(c.total_seats) AS total_seats
FROM coach c
JOIN train t
    ON t.train_id = c.train_id
GROUP BY c.train_id, t.train_name, c.coach_type
ORDER BY c.train_id, c.coach_type;

-- 21) For each junction, count how many different routes pass through that station.
SELECT
    st.station_id,
    st.station_name,
    st.city,
    COUNT(DISTINCT rs.route_id) AS routes_passing_through
FROM station st
JOIN route_station rs
    ON rs.station_id = st.station_id
WHERE st.is_junction = TRUE
GROUP BY st.station_id, st.station_name, st.city
ORDER BY routes_passing_through DESC;

-- 22) Transfer a staff member to a new division, zone and station in one update.
UPDATE staff s
SET
    division_id = 'D004',
    zone_id     = d.zone_id,
    station_id  = 'ST020'
FROM division d
WHERE d.division_id = 'D004'
  AND s.staff_id    = 'S110';

-- 23) See full posting details for some staff including their role, salary and where they are posted.
SELECT
    s.staff_id,
    s.name,
    s.role,
    s.salary,
    s.phone,
    s.email,
    st.station_name,
    st.city,
    d.division_name,
    z.zone_name
FROM staff s
LEFT JOIN station st
    ON st.station_id = s.station_id
JOIN division d
    ON d.division_id = s.division_id
JOIN zone z
    ON z.zone_id = s.zone_id
WHERE s.staff_id IN ('S101','S199');

-- 24) Age distribution of passengers grouped into ranges like <18, 18-35, 35-60 and 60+.
SELECT
    CASE
        WHEN dob > CURRENT_DATE - INTERVAL '18 years'
            THEN 'Less than 18'
        WHEN dob > CURRENT_DATE - INTERVAL '35 years'
             AND dob <= CURRENT_DATE - INTERVAL '18 years'
            THEN '18 - 35'
        WHEN dob > CURRENT_DATE - INTERVAL '60 years'
             AND dob <= CURRENT_DATE - INTERVAL '35 years'
            THEN '35 - 60'
        ELSE '60 or more'
    END AS age_group,
    COUNT(*) AS passenger_count
FROM passenger
GROUP BY age_group
ORDER BY passenger_count DESC;

-- 25) Salary statistics per department like avg, min, max, stddev and how many high earners.
SELECT 
    d.dept_name,
    COUNT(*)                         AS total_staff,
    ROUND(AVG(s.salary)::NUMERIC,2)  AS avg_salary,
    MIN(s.salary)::NUMERIC(10,2)     AS min_salary,
    MAX(s.salary)::NUMERIC(10,2)     AS max_salary,
    ROUND(STDDEV(s.salary)::NUMERIC,2) AS salary_stddev,
    COUNT(CASE WHEN s.salary > 100000 THEN 1 END) AS high_earners
FROM department d
LEFT JOIN staff s
    ON s.dept_id = d.dept_id
GROUP BY d.dept_id, d.dept_name
ORDER BY avg_salary DESC NULLS LAST;

-- 26) List all ticket checkers at a station and show any fine logs they have raised.
SELECT
    st.station_id,
    st.station_name,
    tc.staff_id,
    s.name      AS ticket_checker,
    tc.fine_log
FROM ticket_checker tc
JOIN staff s
    ON s.staff_id = tc.staff_id
JOIN station st
    ON st.station_id = tc.station_id
WHERE st.station_id = 'ST001'
ORDER BY s.name;

-- 27) For each train, show which staff are assigned as driver and guard.
SELECT 
    t.train_id,
    drv.staff_id AS driver_id,
    s_drv.name   AS driver_name,
    grd.staff_id AS guard_id,
    s_grd.name   AS guard_name
FROM train t
LEFT JOIN driver drv
    ON drv.train_id = t.train_id
LEFT JOIN staff s_drv
    ON s_drv.staff_id = drv.staff_id
LEFT JOIN guard grd
    ON grd.train_id = t.train_id
LEFT JOIN staff s_grd
    ON s_grd.staff_id = grd.staff_id
ORDER BY t.train_id;

-- 28) Locomotive inventory with shed info and days since last maintenance service.
SELECT 
    l.loco_id,
    l.loco_class,
    ms.shed_name,
    MAX(mr.maintenance_date) AS last_service_date,
    CURRENT_DATE - MAX(mr.maintenance_date) AS days_since_service
FROM locomotive l
LEFT JOIN maintenance_shed ms
    ON ms.shed_id = l.shed_id
LEFT JOIN division d
    ON d.division_id = ms.division_id
LEFT JOIN train t
    ON t.loco_id = l.loco_id
LEFT JOIN maintenance_record mr
    ON mr.train_id = t.train_id
GROUP BY l.loco_id, l.loco_class, ms.shed_name, d.division_name
ORDER BY days_since_service DESC NULLS LAST;

-- 29) Pull all passengers who are minors (less than 18 years old) based on DOB.
SELECT
    passenger_id,
    pnr,
    name,
    gender,
    dob,
    train_id,
    coach_code,
    seat_number,
    berth_pref
FROM passenger
WHERE dob > CURRENT_DATE - INTERVAL '18 years'
ORDER BY dob DESC;

-- 30) Show all locomotives assigned to a particular maintenance shed.
SELECT 
    ms.shed_id,
    ms.shed_name,
    ms.shed_type,
    l.loco_id,
    l.loco_class
FROM maintenance_shed ms
LEFT JOIN locomotive l
    ON l.shed_id = ms.shed_id
WHERE ms.shed_id = 'SH001'
ORDER BY l.loco_id;

-- 31) Check trains with missing maintenance or maintenance older than a certain time window.
SELECT
    t.train_id,
    t.train_name,
    MAX(mr.maintenance_date) AS last_maintenance,
    CASE
        WHEN MAX(mr.maintenance_date) IS NULL THEN 'NO_RECORD'
        WHEN MAX(mr.maintenance_date) >= CURRENT_DATE - INTERVAL '1 month 5 days'
            THEN 'IN_LAST_1 Month 5 Days'
        ELSE 'OLDER_THAN_1 Month 5 Days'
    END AS maintenance_status
FROM train t
LEFT JOIN maintenance_record mr
    ON mr.train_id = t.train_id
GROUP BY t.train_id, t.train_name
ORDER BY t.train_id;

-- 32) Revenue summary per train including bookings, passengers and total money collected.
SELECT
    tr.train_id,
    tr.train_name,
    COUNT(DISTINCT tk.pnr)      AS total_bookings,
    SUM(tk.passenger_count)     AS total_passengers,
    SUM(p.amount)::NUMERIC(12,2) AS total_revenue
FROM train tr
JOIN tickets tk
    ON tk.schedule_train_id = tr.train_id
JOIN payment p
    ON p.transaction_id = tk.transaction_id
GROUP BY tr.train_id, tr.train_name
ORDER BY total_revenue DESC;

-- 33) Per-day ticket revenue view with transaction count, unique customers and average ticket amount.
SELECT
    DATE(p.payment_time)              AS payment_date,
    COUNT(DISTINCT p.transaction_id)  AS total_transactions,
    COUNT(DISTINCT tk.user_id)        AS unique_customers,
    SUM(p.amount)::NUMERIC(12,2)      AS daily_revenue,
    AVG(p.amount)::NUMERIC(10,2)      AS avg_ticket_price
FROM payment p
LEFT JOIN tickets tk
    ON tk.transaction_id = p.transaction_id
GROUP BY DATE(p.payment_time)
ORDER BY payment_date DESC;

-- 34) Rank trains by how many bookings and passengers they carry to find popular services.
SELECT
    tr.train_id,
    tr.train_name,
    tr.train_type,
    COUNT(DISTINCT tk.pnr)  AS total_bookings,
    SUM(tk.passenger_count) AS total_passengers
FROM train tr
LEFT JOIN tickets tk
    ON tk.schedule_train_id = tr.train_id
GROUP BY tr.train_id, tr.train_name, tr.train_type
HAVING COUNT(DISTINCT tk.pnr) > 0
ORDER BY total_bookings DESC;

-- 35) Compare payment methods like UPI, card, etc. by transaction count and revenue share.
SELECT
    p.method AS payment_method,
    COUNT(DISTINCT p.transaction_id) AS total_transactions,
    COUNT(DISTINCT tk.user_id)       AS unique_customers,
    SUM(p.amount)::NUMERIC(12,2)     AS total_revenue,
    AVG(p.amount)::NUMERIC(10,2)     AS avg_transaction,
    ROUND(
        SUM(p.amount)::NUMERIC / NULLIF((SELECT SUM(amount) FROM payment), 0) * 100
    , 2) AS revenue_share_percent
FROM payment p
LEFT JOIN tickets tk
    ON tk.transaction_id = p.transaction_id
GROUP BY p.method
ORDER BY total_revenue DESC;

-- 36) Zone-wise ticket stats showing how much revenue and how many bookings originate from each zone.
SELECT
    z.zone_id,
    z.zone_name,
    SUM(p.amount)::NUMERIC(12,2) AS total_revenue,
    COUNT(DISTINCT tk.pnr)       AS total_bookings
FROM tickets tk
JOIN station st
    ON st.station_id = tk.boarding_station
JOIN division d
    ON d.division_id = st.division_id
JOIN zone z
    ON z.zone_id = d.zone_id
JOIN payment p
    ON p.transaction_id = tk.transaction_id
GROUP BY z.zone_id, z.zone_name
ORDER BY total_revenue DESC;

-- 37) List all staff who are working in a particular role, for example HR Assistant.
SELECT
    staff_id,
    name,
    role,
    dept_id,
    station_id,
    division_id,
    zone_id,
    phone,
    email,
    salary
FROM staff
WHERE role = 'HR Assistant'
ORDER BY name;

-- 38) Daily passenger load based on when people actually travel (schedule date).
SELECT
    DATE(tk.schedule_starting_ts) AS travel_date,
    SUM(tk.passenger_count)       AS total_passengers
FROM tickets tk
GROUP BY DATE(tk.schedule_starting_ts)
ORDER BY travel_date DESC;

-- 39) Show all the staff who worked on a single maintenance record (one maintenance_id).
SELECT
    mr.maintenance_id,
    mr.train_id,
    mr.maintenance_date,
    s.staff_id,
    s.role       AS staff_role
FROM maintenance_record mr
JOIN maintenance_staff ms
    ON mr.maintenance_id = ms.maintenance_id
JOIN staff s
    ON s.staff_id = ms.staff_id
WHERE mr.maintenance_id = 'MR001'
ORDER BY s.staff_id;

-- 40) Average fare paid per passenger for each train using tickets and payments.
SELECT
    tr.train_id,
    tr.train_name,
    ROUND(
        SUM(p.amount) / NULLIF(SUM(tk.passenger_count), 0)
    , 2) AS avg_fare_per_passenger
FROM train tr
JOIN tickets tk
    ON tk.schedule_train_id = tr.train_id
JOIN payment p
    ON p.transaction_id = tk.transaction_id
GROUP BY tr.train_id, tr.train_name
ORDER BY avg_fare_per_passenger DESC;

-- 41) Find power users who have booked at least three different tickets.
SELECT
    ru.user_id,
    ru.name,
    COUNT(DISTINCT tk.pnr) AS total_bookings
FROM registered_user ru
JOIN tickets tk
    ON tk.user_id = ru.user_id
GROUP BY ru.user_id, ru.name
HAVING COUNT(DISTINCT tk.pnr) >= 3
ORDER BY total_bookings DESC, ru.user_id;

-- 42) Division-wise staff strength and average salary along with their zone.
SELECT
    d.division_id,
    d.division_name,
    z.zone_name,
    COUNT(s.staff_id)                  AS staff_count,
    ROUND(AVG(s.salary)::NUMERIC, 2)   AS avg_salary
FROM division d
JOIN zone z
    ON z.zone_id = d.zone_id
LEFT JOIN staff s
    ON s.division_id = d.division_id
GROUP BY d.division_id, d.division_name, z.zone_name
ORDER BY staff_count DESC;

-- 43) Role-wise breakdown of staff count and how much salary is spent on each role.
SELECT
    s.role,
    COUNT(*)      AS staff_count,
    SUM(s.salary) AS total_salary,
    AVG(s.salary) AS avg_salary
FROM staff s
GROUP BY s.role
ORDER BY total_salary DESC;

-- 44) For each train, see average group size by checking passengers per booking.
SELECT
    tr.train_id,
    tr.train_name,
    COUNT(DISTINCT tk.pnr)              AS total_bookings,
    SUM(tk.passenger_count)             AS total_passengers,
    ROUND(
        (SUM(tk.passenger_count)::numeric /
         NULLIF(COUNT(DISTINCT tk.pnr), 0))
    , 2) AS avg_passengers_per_booking
FROM train tr
JOIN tickets tk
    ON tk.schedule_train_id = tr.train_id
GROUP BY tr.train_id, tr.train_name
HAVING COUNT(DISTINCT tk.pnr) > 0
ORDER BY avg_passengers_per_booking DESC, tr.train_id;

-- 45) Top five stations where trains get delayed the most, along with how many reports exist.
SELECT
    st.station_id,
    st.station_name,
    st.city,
    ROUND(AVG(lts.delay_minutes)::numeric, 2) AS avg_delay_minutes,
    COUNT(*)                                   AS reports
FROM live_train_status lts
JOIN station st
    ON st.station_id = lts.station_id
GROUP BY st.station_id, st.station_name, st.city
HAVING COUNT(*) > 0
ORDER BY avg_delay_minutes DESC, reports DESC
LIMIT 5;

-- 46) Rank users based on how much money they have spent on tickets and how many bookings they made.
SELECT
    ru.user_id,
    ru.name,
    SUM(p.amount)::NUMERIC(12,2) AS total_spent,
    COUNT(DISTINCT tk.pnr)       AS total_bookings
FROM registered_user ru
JOIN tickets tk
    ON tk.user_id = ru.user_id
JOIN payment p
    ON p.transaction_id = tk.transaction_id
GROUP BY ru.user_id, ru.name
ORDER BY total_spent DESC
LIMIT 10;

-- 47) List all trains whose route passes through a specific junction station code.
SELECT DISTINCT
    t.train_id,
    t.train_name,
    r.route_name
FROM train t
JOIN route r
    ON r.route_id = t.route_id
JOIN route_station rs
    ON rs.route_id = r.route_id
JOIN station st
    ON st.station_id = rs.station_id
WHERE st.station_id = 'ST004'
ORDER BY t.train_id;

-- 48) Zone-wise average ticket price per passenger using boarding station zones.
SELECT
    z.zone_id,
    z.zone_name,
    SUM(p.amount)::numeric(12,2)         AS total_revenue,
    SUM(tk.passenger_count)              AS total_passengers,
    ROUND(
        SUM(p.amount)::numeric /
        NULLIF(SUM(tk.passenger_count), 0)
    , 2) AS avg_price_per_passenger
FROM tickets tk
JOIN payment p
    ON p.transaction_id = tk.transaction_id
JOIN station st
    ON st.station_id = tk.boarding_station
JOIN division d
    ON d.division_id = st.division_id
JOIN zone z
    ON z.zone_id = d.zone_id
GROUP BY z.zone_id, z.zone_name
ORDER BY avg_price_per_passenger DESC;

-- 49) All upcoming schedules for a given train with departure, arrival and station names.
SELECT
    sch.train_id,
    t.train_name,
    sch.starting_ts    AS departure_time,
    sch.ending_ts      AS arrival_time,
    src.station_name   AS source_station,
    dst.station_name   AS destination_station
FROM schedule sch
JOIN train t
    ON t.train_id = sch.train_id
JOIN station src
    ON src.station_id = sch.source_station_id
JOIN station dst
    ON dst.station_id = sch.destination_station_id
WHERE sch.train_id = 'TR019'
  AND sch.starting_ts > CURRENT_TIMESTAMP
ORDER BY sch.starting_ts;

-- 50) For a train, compare configured seats in each coach with how many seats exist in the seat table.
SELECT
    c.train_id,
    t.train_name,
    c.coach_code,
    c.coach_type,
    c.total_seats AS seats_configured,
    COUNT(s.seat_number) AS seats_defined
FROM coach c
JOIN train t
    ON t.train_id = c.train_id
LEFT JOIN seat s
    ON s.train_id = c.train_id
   AND s.coach_code = c.coach_code
WHERE c.train_id = 'TR001'
GROUP BY c.train_id, t.train_name, c.coach_code, c.coach_type, c.total_seats
ORDER BY c.coach_code;
