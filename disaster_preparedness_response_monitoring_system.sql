
-- ============================================================
-- DISASTER PREPAREDNESS AND RESPONSE MONITORING SYSTEM
-- Supabase PostgreSQL Database
-- Scope: First Congressional District, Cagayan de Oro City
-- ============================================================

create extension if not exists pgcrypto;

create schema if not exists private;

-- ============================================================
-- 1. LOOKUP TABLES
-- ============================================================

create table public.districts (
    district_id smallserial primary key,
    district_name varchar(100) not null unique,
    description text
);

create table public.account_statuses (
    status_id smallserial primary key,
    status_name varchar(30) not null unique
);

create table public.disaster_types (
    disaster_type_id smallserial primary key,
    type_name varchar(80) not null unique,
    description text
);

create table public.severity_levels (
    severity_id smallserial primary key,
    severity_name varchar(30) not null unique,
    severity_rank smallint not null unique
);

create table public.report_statuses (
    report_status_id smallserial primary key,
    status_name varchar(40) not null unique
);

create table public.request_statuses (
    request_status_id smallserial primary key,
    status_name varchar(40) not null unique,
    is_final boolean not null default false
);

create table public.priority_levels (
    priority_id smallserial primary key,
    priority_name varchar(30) not null unique,
    priority_rank smallint not null unique
);

create table public.evacuation_center_types (
    center_type_id smallserial primary key,
    type_name varchar(80) not null unique
);

create table public.incident_categories (
    incident_category_id smallserial primary key,
    category_name varchar(100) not null unique
);

create table public.request_categories (
    request_category_id smallserial primary key,
    category_name varchar(100) not null unique
);

create table public.measurement_units (
    unit_id smallserial primary key,
    unit_name varchar(50) not null unique,
    abbreviation varchar(15) not null unique
);

create table public.relief_distribution_statuses (
    distribution_status_id smallserial primary key,
    status_name varchar(40) not null unique
);

create table public.notification_types (
    notification_type_id smallserial primary key,
    type_name varchar(60) not null unique
);

-- ============================================================
-- 2. GEOGRAPHY AND BARANGAYS
-- ============================================================

create table public.barangays (
    barangay_id uuid primary key default gen_random_uuid(),
    district_id smallint not null references public.districts(district_id),
    barangay_name varchar(100) not null unique,
    address text,
    latitude numeric(10,7),
    longitude numeric(10,7),
    contact_number varchar(30),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    check (latitude is null or latitude between -90 and 90),
    check (longitude is null or longitude between -180 and 180)
);

-- ============================================================
-- 3. RBAC: ROLES, PERMISSIONS, USER PROFILES
-- ============================================================

create table public.roles (
    role_id smallserial primary key,
    role_code varchar(50) not null unique,
    role_name varchar(100) not null unique,
    description text,
    is_system_role boolean not null default true
);

create table public.permissions (
    permission_id smallserial primary key,
    permission_code varchar(100) not null unique,
    permission_name varchar(120) not null,
    module_name varchar(80) not null,
    description text
);

create table public.role_permissions (
    role_id smallint not null references public.roles(role_id)
        on delete cascade,
    permission_id smallint not null references public.permissions(permission_id)
        on delete cascade,
    primary key (role_id, permission_id)
);

create table public.user_profiles (
    user_id uuid primary key references auth.users(id)
        on delete cascade,
    barangay_id uuid references public.barangays(barangay_id),
    full_name varchar(150) not null,
    email varchar(255) not null,
    contact_number varchar(30),
    position_title varchar(100),
    account_status_id smallint not null
        references public.account_statuses(status_id),
    is_barangay_reporter boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (
        (is_barangay_reporter = false)
        or (barangay_id is not null)
    )
);

create unique index one_active_reporter_per_barangay
on public.user_profiles(barangay_id)
where is_barangay_reporter = true;

create table public.user_roles (
    user_id uuid not null references public.user_profiles(user_id)
        on delete cascade,
    role_id smallint not null references public.roles(role_id),
    assigned_by uuid references public.user_profiles(user_id),
    assigned_at timestamptz not null default now(),
    primary key (user_id, role_id)
);

-- ============================================================
-- 4. DISASTER EVENTS
-- ============================================================

create table public.disaster_events (
    disaster_id uuid primary key default gen_random_uuid(),
    disaster_type_id smallint not null
        references public.disaster_types(disaster_type_id),
    severity_id smallint references public.severity_levels(severity_id),
    event_name varchar(180) not null,
    description text,
    date_started timestamptz not null,
    date_ended timestamptz,
    declared_by uuid references public.user_profiles(user_id),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (date_ended is null or date_ended >= date_started)
);

create table public.disaster_event_barangays (
    disaster_id uuid not null
        references public.disaster_events(disaster_id) on delete cascade,
    barangay_id uuid not null
        references public.barangays(barangay_id),
    impact_description text,
    recorded_at timestamptz not null default now(),
    primary key (disaster_id, barangay_id)
);

-- ============================================================
-- 5. SITUATION REPORTS AND REPORT HISTORY
-- ============================================================

create table public.situation_reports (
    report_id uuid primary key default gen_random_uuid(),
    report_number bigint generated always as identity unique,
    disaster_id uuid not null
        references public.disaster_events(disaster_id),
    barangay_id uuid not null
        references public.barangays(barangay_id),
    submitted_by uuid not null
        references public.user_profiles(user_id),
    report_status_id smallint not null
        references public.report_statuses(report_status_id),
    report_title varchar(180) not null,
    situation_summary text not null,
    affected_households integer not null default 0,
    affected_persons integer not null default 0,
    injured_persons integer not null default 0,
    missing_persons integer not null default 0,
    deceased_persons integer not null default 0,
    displaced_persons integer not null default 0,
    infrastructure_damage_summary text,
    immediate_needs text,
    latitude numeric(10,7),
    longitude numeric(10,7),
    submitted_at timestamptz not null default now(),
    reviewed_by uuid references public.user_profiles(user_id),
    reviewed_at timestamptz,
    review_notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (affected_households >= 0),
    check (affected_persons >= 0),
    check (injured_persons >= 0),
    check (missing_persons >= 0),
    check (deceased_persons >= 0),
    check (displaced_persons >= 0)
);

-- Immutable snapshots of submitted report versions.
create table public.situation_report_history (
    history_id uuid primary key default gen_random_uuid(),
    report_id uuid not null
        references public.situation_reports(report_id) on delete cascade,
    version_number integer not null,
    changed_by uuid references public.user_profiles(user_id),
    change_reason text,
    snapshot jsonb not null,
    recorded_at timestamptz not null default now(),
    unique (report_id, version_number)
);

create table public.incident_reports (
    incident_report_id uuid primary key default gen_random_uuid(),
    report_id uuid not null
        references public.situation_reports(report_id) on delete cascade,
    incident_category_id smallint not null
        references public.incident_categories(incident_category_id),
    incident_title varchar(180) not null,
    incident_description text,
    location_description text,
    latitude numeric(10,7),
    longitude numeric(10,7),
    severity_id smallint references public.severity_levels(severity_id),
    incident_time timestamptz,
    created_at timestamptz not null default now()
);

create table public.report_attachments (
    attachment_id uuid primary key default gen_random_uuid(),
    report_id uuid not null
        references public.situation_reports(report_id) on delete cascade,
    uploaded_by uuid not null references public.user_profiles(user_id),
    storage_path text not null,
    original_file_name varchar(255),
    content_type varchar(100),
    file_size_bytes bigint,
    uploaded_at timestamptz not null default now(),
    check (file_size_bytes is null or file_size_bytes >= 0)
);

-- ============================================================
-- 6. AFFECTED POPULATION DETAILS
-- ============================================================

create table public.affected_population_records (
    population_record_id uuid primary key default gen_random_uuid(),
    report_id uuid not null
        references public.situation_reports(report_id) on delete cascade,
    population_group varchar(80) not null,
    persons_count integer not null default 0,
    households_count integer not null default 0,
    notes text,
    created_at timestamptz not null default now(),
    check (persons_count >= 0),
    check (households_count >= 0),
    unique (report_id, population_group)
);

-- Avoid storing names or sensitive personal information unless required
-- and approved by the client and research ethics/data privacy process.

-- ============================================================
-- 7. EVACUATION CENTERS AND OCCUPANCY HISTORY
-- ============================================================

create table public.evacuation_centers (
    center_id uuid primary key default gen_random_uuid(),
    barangay_id uuid not null
        references public.barangays(barangay_id),
    center_type_id smallint not null
        references public.evacuation_center_types(center_type_id),
    center_name varchar(180) not null,
    address text not null,
    capacity_persons integer not null default 0,
    capacity_families integer,
    latitude numeric(10,7),
    longitude numeric(10,7),
    contact_person varchar(150),
    contact_number varchar(30),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (capacity_persons >= 0),
    check (capacity_families is null or capacity_families >= 0),
    unique (barangay_id, center_name)
);

create table public.evacuation_occupancy_snapshots (
    occupancy_id uuid primary key default gen_random_uuid(),
    center_id uuid not null
        references public.evacuation_centers(center_id),
    report_id uuid references public.situation_reports(report_id),
    persons_count integer not null default 0,
    families_count integer not null default 0,
    available_spaces integer,
    recorded_by uuid not null references public.user_profiles(user_id),
    recorded_at timestamptz not null default now(),
    notes text,
    check (persons_count >= 0),
    check (families_count >= 0),
    check (available_spaces is null or available_spaces >= 0)
);

create table public.evacuation_records (
    evacuation_record_id uuid primary key default gen_random_uuid(),
    center_id uuid not null
        references public.evacuation_centers(center_id),
    disaster_id uuid not null
        references public.disaster_events(disaster_id),
    household_reference varchar(100),
    persons_count integer not null default 1,
    arrival_time timestamptz not null default now(),
    departure_time timestamptz,
    recorded_by uuid not null references public.user_profiles(user_id),
    notes text,
    check (persons_count > 0),
    check (departure_time is null or departure_time >= arrival_time)
);

-- ============================================================
-- 8. ASSISTANCE REQUESTS AND TRACKING HISTORY
-- ============================================================

create table public.assistance_requests (
    request_id uuid primary key default gen_random_uuid(),
    request_number bigint generated always as identity unique,
    disaster_id uuid not null
        references public.disaster_events(disaster_id),
    barangay_id uuid not null
        references public.barangays(barangay_id),
    report_id uuid references public.situation_reports(report_id),
    request_category_id smallint not null
        references public.request_categories(request_category_id),
    priority_id smallint not null
        references public.priority_levels(priority_id),
    request_status_id smallint not null
        references public.request_statuses(request_status_id),
    requested_by uuid not null references public.user_profiles(user_id),
    request_title varchar(180) not null,
    request_description text not null,
    requested_persons integer,
    requested_at timestamptz not null default now(),
    assigned_to uuid references public.user_profiles(user_id),
    reviewed_at timestamptz,
    closed_at timestamptz,
    closure_notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (requested_persons is null or requested_persons >= 0)
);

create table public.assistance_request_items (
    request_item_id uuid primary key default gen_random_uuid(),
    request_id uuid not null
        references public.assistance_requests(request_id) on delete cascade,
    item_description varchar(180) not null,
    quantity numeric(12,2) not null,
    unit_id smallint not null
        references public.measurement_units(unit_id),
    fulfilled_quantity numeric(12,2) not null default 0,
    notes text,
    check (quantity > 0),
    check (fulfilled_quantity >= 0),
    check (fulfilled_quantity <= quantity)
);

create table public.assistance_request_history (
    request_history_id uuid primary key default gen_random_uuid(),
    request_id uuid not null
        references public.assistance_requests(request_id) on delete cascade,
    previous_status_id smallint
        references public.request_statuses(request_status_id),
    new_status_id smallint not null
        references public.request_statuses(request_status_id),
    changed_by uuid not null references public.user_profiles(user_id),
    remarks text,
    changed_at timestamptz not null default now()
);

create table public.request_assignments (
    assignment_id uuid primary key default gen_random_uuid(),
    request_id uuid not null
        references public.assistance_requests(request_id) on delete cascade,
    assigned_to uuid not null references public.user_profiles(user_id),
    assigned_by uuid not null references public.user_profiles(user_id),
    assignment_notes text,
    assigned_at timestamptz not null default now(),
    completed_at timestamptz
);

create table public.request_tracking_updates (
    tracking_id uuid primary key default gen_random_uuid(),
    request_id uuid not null
        references public.assistance_requests(request_id) on delete cascade,
    updated_by uuid not null references public.user_profiles(user_id),
    tracking_status varchar(80) not null,
    location_description text,
    update_notes text,
    latitude numeric(10,7),
    longitude numeric(10,7),
    recorded_at timestamptz not null default now()
);

-- ============================================================
-- 9. RELIEF INVENTORY AND DISTRIBUTION
-- ============================================================

create table public.relief_items (
    item_id uuid primary key default gen_random_uuid(),
    item_code varchar(50) not null unique,
    item_name varchar(150) not null unique,
    description text,
    unit_id smallint not null references public.measurement_units(unit_id),
    minimum_stock numeric(12,2) not null default 0,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    check (minimum_stock >= 0)
);

create table public.relief_stock_locations (
    stock_location_id uuid primary key default gen_random_uuid(),
    location_name varchar(150) not null unique,
    address text,
    barangay_id uuid references public.barangays(barangay_id),
    is_active boolean not null default true
);

create table public.relief_stock_movements (
    movement_id uuid primary key default gen_random_uuid(),
    item_id uuid not null references public.relief_items(item_id),
    stock_location_id uuid not null
        references public.relief_stock_locations(stock_location_id),
    movement_type varchar(30) not null
        check (movement_type in ('RECEIPT', 'DISTRIBUTION', 'ADJUSTMENT', 'TRANSFER_IN', 'TRANSFER_OUT')),
    quantity numeric(12,2) not null,
    reference_number varchar(100),
    movement_notes text,
    recorded_by uuid not null references public.user_profiles(user_id),
    movement_time timestamptz not null default now(),
    check (quantity > 0)
);

create table public.relief_distributions (
    distribution_id uuid primary key default gen_random_uuid(),
    distribution_number bigint generated always as identity unique,
    disaster_id uuid not null
        references public.disaster_events(disaster_id),
    barangay_id uuid not null
        references public.barangays(barangay_id),
    request_id uuid references public.assistance_requests(request_id),
    distribution_status_id smallint not null
        references public.relief_distribution_statuses(distribution_status_id),
    prepared_by uuid not null references public.user_profiles(user_id),
    received_by_name varchar(150),
    recipient_role varchar(100),
    acknowledgment_reference varchar(150),
    distribution_location text,
    prepared_at timestamptz not null default now(),
    released_at timestamptz,
    acknowledged_at timestamptz,
    notes text
);

create table public.relief_distribution_items (
    distribution_item_id uuid primary key default gen_random_uuid(),
    distribution_id uuid not null
        references public.relief_distributions(distribution_id) on delete cascade,
    item_id uuid not null references public.relief_items(item_id),
    quantity numeric(12,2) not null,
    unit_id smallint not null references public.measurement_units(unit_id),
    stock_location_id uuid references public.relief_stock_locations(stock_location_id),
    check (quantity > 0),
    unique (distribution_id, item_id)
);

create table public.distribution_acknowledgments (
    acknowledgment_id uuid primary key default gen_random_uuid(),
    distribution_id uuid not null
        references public.relief_distributions(distribution_id),
    acknowledged_by uuid references public.user_profiles(user_id),
    recipient_name varchar(150) not null,
    acknowledgment_method varchar(50) not null,
    proof_storage_path text,
    remarks text,
    acknowledged_at timestamptz not null default now()
);

-- ============================================================
-- 10. NOTIFICATIONS AND AUDIT LOGS
-- ============================================================

create table public.notifications (
    notification_id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.user_profiles(user_id)
        on delete cascade,
    notification_type_id smallint not null
        references public.notification_types(notification_type_id),
    title varchar(180) not null,
    message text not null,
    related_entity_type varchar(80),
    related_entity_id uuid,
    is_read boolean not null default false,
    created_at timestamptz not null default now(),
    read_at timestamptz
);

create table public.audit_logs (
    audit_id bigint generated always as identity primary key,
    actor_user_id uuid references public.user_profiles(user_id),
    action_type varchar(50) not null,
    entity_name varchar(100) not null,
    entity_id text,
    old_values jsonb,
    new_values jsonb,
    ip_address inet,
    user_agent text,
    occurred_at timestamptz not null default now()
);

-- ============================================================
-- 11. INDEXES
-- ============================================================

create index idx_profiles_barangay
    on public.user_profiles(barangay_id);

create index idx_user_roles_role
    on public.user_roles(role_id);

create index idx_events_dates
    on public.disaster_events(date_started, date_ended);

create index idx_reports_barangay_time
    on public.situation_reports(barangay_id, submitted_at desc);

create index idx_reports_disaster
    on public.situation_reports(disaster_id);

create index idx_report_history
    on public.situation_report_history(report_id, version_number desc);

create index idx_evacuation_center_barangay
    on public.evacuation_centers(barangay_id);

create index idx_occupancy_center_time
    on public.evacuation_occupancy_snapshots(center_id, recorded_at desc);

create index idx_requests_barangay_time
    on public.assistance_requests(barangay_id, requested_at desc);

create index idx_requests_status
    on public.assistance_requests(request_status_id, priority_id);

create index idx_request_history
    on public.assistance_request_history(request_id, changed_at desc);

create index idx_request_tracking
    on public.request_tracking_updates(request_id, recorded_at desc);

create index idx_relief_movements_item
    on public.relief_stock_movements(item_id, movement_time desc);

create index idx_distributions_barangay
    on public.relief_distributions(barangay_id, prepared_at desc);

create index idx_notifications_user
    on public.notifications(user_id, is_read, created_at desc);

create index idx_audit_logs_entity
    on public.audit_logs(entity_name, entity_id, occurred_at desc);

-- ============================================================
-- 12. SEED LOOKUP DATA
-- ============================================================

insert into public.districts (district_name, description)
values
('First Congressional District', 'First district of Cagayan de Oro City'),
('Second Congressional District', 'Second district of Cagayan de Oro City')
on conflict (district_name) do nothing;

insert into public.account_statuses (status_name)
values ('Pending'), ('Active'), ('Suspended'), ('Deactivated')
on conflict (status_name) do nothing;

insert into public.disaster_types (type_name)
values
('Flood'), ('Landslide'), ('Fire'), ('Earthquake'),
('Severe Weather'), ('Storm Surge'), ('Other')
on conflict (type_name) do nothing;

insert into public.severity_levels (severity_name, severity_rank)
values ('Low',1), ('Moderate',2), ('High',3), ('Critical',4)
on conflict (severity_name) do nothing;

insert into public.report_statuses (status_name)
values ('Draft'), ('Submitted'), ('Under Review'), ('Verified'), ('Returned for Revision')
on conflict (status_name) do nothing;

insert into public.request_statuses (status_name, is_final)
values
('Submitted',false), ('Under Review',false), ('Approved',false),
('Rejected',true), ('Assigned',false), ('In Progress',false),
('Partially Fulfilled',false), ('Fulfilled',true), ('Closed',true)
on conflict (status_name) do nothing;

insert into public.priority_levels (priority_name, priority_rank)
values ('Low',1), ('Normal',2), ('High',3), ('Urgent',4)
on conflict (priority_name) do nothing;

insert into public.evacuation_center_types (type_name)
values ('School'), ('Covered Court'), ('Government Facility'),
('Church'), ('Temporary Shelter'), ('Other')
on conflict (type_name) do nothing;

insert into public.incident_categories (category_name)
values ('Flooding'), ('Structural Damage'), ('Road Blockage'),
('Fire Incident'), ('Medical Emergency'), ('Missing Person'),
('Power Interruption'), ('Other')
on conflict (category_name) do nothing;

insert into public.request_categories (category_name)
values ('Food'), ('Drinking Water'), ('Medical Supplies'),
('Rescue Assistance'), ('Evacuation Transport'),
('Temporary Shelter'), ('Clothing'), ('Hygiene Kits'),
('Heavy Equipment'), ('Other')
on conflict (category_name) do nothing;

insert into public.measurement_units (unit_name, abbreviation)
values ('Piece','pc'), ('Pack','pack'), ('Box','box'),
('Kilogram','kg'), ('Liter','L'), ('Bottle','bottle'),
('Sack','sack'), ('Set','set'), ('Family Kit','kit')
on conflict (unit_name) do nothing;

insert into public.relief_distribution_statuses (status_name)
values ('Prepared'), ('Approved'), ('Released'), ('Acknowledged'), ('Cancelled')
on conflict (status_name) do nothing;

insert into public.notification_types (type_name)
values ('Report Update'), ('Request Update'), ('Assignment'),
('Distribution Update'), ('System Alert')
on conflict (type_name) do nothing;

insert into public.roles (role_code, role_name, description)
values
('super_admin','Super Administrator','Manages system configuration and accounts'),
('city_admin','City Administrator','Oversees consolidated disaster operations'),
('barangay_reporter','Barangay Reporter','Submits official reports for one assigned barangay'),
('relief_coordinator','Relief Coordinator','Coordinates relief stock and distribution'),
('evacuation_officer','Evacuation Officer','Maintains evacuation center and occupancy information'),
('viewer','Read-Only Viewer','Views explicitly authorized records')
on conflict (role_code) do nothing;

insert into public.permissions (permission_code, permission_name, module_name)
values
('users.manage','Manage Users','Users'),
('roles.manage','Manage Roles and Permissions','RBAC'),
('events.manage','Manage Disaster Events','Disasters'),
('reports.submit','Submit Situation Reports','Reports'),
('reports.view_barangay','View Assigned Barangay Reports','Reports'),
('reports.view_all','View All Barangay Reports','Reports'),
('reports.review','Review Situation Reports','Reports'),
('requests.submit','Submit Assistance Requests','Requests'),
('requests.review','Review Assistance Requests','Requests'),
('requests.assign','Assign Assistance Requests','Requests'),
('requests.track','Update Request Tracking','Requests'),
('evacuation.manage','Manage Evacuation Centers','Evacuation'),
('evacuation.update','Update Evacuation Occupancy','Evacuation'),
('relief.manage_stock','Manage Relief Stock','Relief'),
('relief.distribute','Record Relief Distribution','Relief'),
('audit.view','View Audit Logs','Audit')
on conflict (permission_code) do nothing;

-- Map role codes to permissions.
insert into public.role_permissions (role_id, permission_id)
select r.role_id, p.permission_id
from public.roles r
cross join public.permissions p
where
    r.role_code = 'super_admin'
    or (r.role_code = 'city_admin' and p.permission_code in (
        'events.manage','reports.view_all','reports.review',
        'requests.review','requests.assign','requests.track',
        'evacuation.manage','evacuation.update','audit.view'
    ))
    or (r.role_code = 'barangay_reporter' and p.permission_code in (
        'reports.submit','reports.view_barangay','requests.submit'
    ))
    or (r.role_code = 'relief_coordinator' and p.permission_code in (
        'reports.view_all','requests.review','requests.assign',
        'requests.track','relief.manage_stock','relief.distribute'
    ))
    or (r.role_code = 'evacuation_officer' and p.permission_code in (
        'reports.view_all','evacuation.manage','evacuation.update'
    ))
    or (r.role_code = 'viewer' and p.permission_code in (
        'reports.view_all'
    ))
on conflict do nothing;

-- Seed the 24 barangays in the first congressional district.
insert into public.barangays (district_id, barangay_name)
select d.district_id, b.barangay_name
from public.districts d
cross join (values
    ('Baikingon'), ('Balulang'), ('Bayabas'), ('Bayanga'),
    ('Besigan'), ('Bonbon'), ('Bulua'), ('Canitoan'),
    ('Carmen'), ('Dansolihon'), ('Iponan'), ('Kauswagan'),
    ('Lumbia'), ('Mambuaya'), ('Pagalungan'), ('Pagatpat'),
    ('Patag'), ('Pigsag-an'), ('San Simon'), ('Taglimao'),
    ('Tagpangi'), ('Tignapoloan'), ('Tuburan'), ('Tumpagon')
) as b(barangay_name)
where d.district_name = 'First Congressional District'
on conflict (barangay_name) do nothing;

-- ============================================================
-- 13. HELPER FUNCTIONS FOR ACCESS CONTROL
-- ============================================================

create or replace function private.has_role(required_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.user_roles ur
        join public.roles r on r.role_id = ur.role_id
        join public.user_profiles up on up.user_id = ur.user_id
        join public.account_statuses s
          on s.status_id = up.account_status_id
        where ur.user_id = (select auth.uid())
          and r.role_code = required_role
          and s.status_name = 'Active'
    );
$$;

create or replace function private.my_barangay_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select up.barangay_id
    from public.user_profiles up
    join public.account_statuses s
      on s.status_id = up.account_status_id
    where up.user_id = (select auth.uid())
      and s.status_name = 'Active'
    limit 1;
$$;

create or replace function private.has_permission(required_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.user_roles ur
        join public.role_permissions rp on rp.role_id = ur.role_id
        join public.permissions p on p.permission_id = rp.permission_id
        join public.user_profiles up on up.user_id = ur.user_id
        join public.account_statuses s
          on s.status_id = up.account_status_id
        where ur.user_id = (select auth.uid())
          and p.permission_code = required_permission
          and s.status_name = 'Active'
    );
$$;

revoke all on function private.has_role(text) from public;
revoke all on function private.my_barangay_id() from public;
revoke all on function private.has_permission(text) from public;

grant usage on schema private to authenticated;
grant execute on function private.has_role(text) to authenticated;
grant execute on function private.my_barangay_id() to authenticated;
grant execute on function private.has_permission(text) to authenticated;

-- ============================================================
-- 14. ENABLE RLS ON ALL PUBLIC TABLES
-- ============================================================

do $$
declare
    t record;
begin
    for t in
        select tablename
        from pg_tables
        where schemaname = 'public'
    loop
        execute format(
            'alter table public.%I enable row level security',
            t.tablename
        );
    end loop;
end $$;

-- Remove default API access first. Add only explicit grants below.
revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
grant insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Lookup data can be read by signed-in users.
create policy "active users read districts"
on public.districts for select to authenticated
using (auth.uid() is not null);

create policy "active users read barangays"
on public.barangays for select to authenticated
using (auth.uid() is not null);

create policy "active users read lookup tables"
on public.account_statuses for select to authenticated
using (auth.uid() is not null);

create policy "active users read disaster types"
on public.disaster_types for select to authenticated
using (auth.uid() is not null);

create policy "active users read severity levels"
on public.severity_levels for select to authenticated
using (auth.uid() is not null);

create policy "active users read report statuses"
on public.report_statuses for select to authenticated
using (auth.uid() is not null);

create policy "active users read request statuses"
on public.request_statuses for select to authenticated
using (auth.uid() is not null);

create policy "active users read priority levels"
on public.priority_levels for select to authenticated
using (auth.uid() is not null);

create policy "active users read center types"
on public.evacuation_center_types for select to authenticated
using (auth.uid() is not null);

create policy "active users read incident categories"
on public.incident_categories for select to authenticated
using (auth.uid() is not null);

create policy "active users read request categories"
on public.request_categories for select to authenticated
using (auth.uid() is not null);

create policy "active users read units"
on public.measurement_units for select to authenticated
using (auth.uid() is not null);

create policy "active users read distribution statuses"
on public.relief_distribution_statuses for select to authenticated
using (auth.uid() is not null);

create policy "active users read notification types"
on public.notification_types for select to authenticated
using (auth.uid() is not null);

create policy "active users read roles"
on public.roles for select to authenticated
using (auth.uid() is not null);

create policy "active users read permissions"
on public.permissions for select to authenticated
using (auth.uid() is not null);

create policy "active users read role permissions"
on public.role_permissions for select to authenticated
using (auth.uid() is not null);

-- User profiles: users can view their own profile;
-- city admins and super admins can view all profiles.
create policy "profiles read own or administrators"
on public.user_profiles for select to authenticated
using (
    user_id = (select auth.uid())
    or (select private.has_role('super_admin'))
    or (select private.has_role('city_admin'))
);

create policy "profiles update own limited app fields"
on public.user_profiles for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy "administrators manage profiles"
on public.user_profiles for all to authenticated
using (
    (select private.has_role('super_admin'))
    or (select private.has_role('city_admin'))
)
with check (
    (select private.has_role('super_admin'))
    or (select private.has_role('city_admin'))
);

create policy "users read own role assignments"
on public.user_roles for select to authenticated
using (
    user_id = (select auth.uid())
    or (select private.has_role('super_admin'))
    or (select private.has_role('city_admin'))
);

create policy "super admin manages user roles"
on public.user_roles for all to authenticated
using ((select private.has_role('super_admin')))
with check ((select private.has_role('super_admin')));

-- Disaster events: designated administrators manage them.
create policy "users view disaster events"
on public.disaster_events for select to authenticated
using (auth.uid() is not null);

create policy "administrators manage disaster events"
on public.disaster_events for all to authenticated
using (
    (select private.has_role('super_admin'))
    or (select private.has_role('city_admin'))
)
with check (
    (select private.has_role('super_admin'))
    or (select private.has_role('city_admin'))
);

create policy "users view event barangay mapping"
on public.disaster_event_barangays for select to authenticated
using (auth.uid() is not null);

create policy "administrators manage event barangays"
on public.disaster_event_barangays for all to authenticated
using (
    (select private.has_role('super_admin'))
    or (select private.has_role('city_admin'))
)
with check (
    (select private.has_role('super_admin'))
    or (select private.has_role('city_admin'))
);

-- Reports: barangay reporters see their own barangay;
-- city-level authorized roles can see all reports.
create policy "read permitted situation reports"
on public.situation_reports for select to authenticated
using (
    barangay_id = (select private.my_barangay_id())
    or (select private.has_permission('reports.view_all'))
    or (select private.has_role('super_admin'))
);

create policy "barangay reporter submits reports"
on public.situation_reports for insert to authenticated
with check (
    barangay_id = (select private.my_barangay_id())
    and submitted_by = (select auth.uid())
    and (select private.has_permission('reports.submit'))
);

create policy "authorized reviewers update reports"
on public.situation_reports for update to authenticated
using (
    (select private.has_permission('reports.review'))
    or (
        barangay_id = (select private.my_barangay_id())
        and submitted_by = (select auth.uid())
        and (select private.has_permission('reports.submit'))
    )
)
with check (
    (select private.has_permission('reports.review'))
    or (
        barangay_id = (select private.my_barangay_id())
        and submitted_by = (select auth.uid())
    )
);

create policy "administrators delete reports"
on public.situation_reports for delete to authenticated
using ((select private.has_role('super_admin')));

create policy "read permitted report history"
on public.situation_report_history for select to authenticated
using (
    exists (
        select 1 from public.situation_reports r
        where r.report_id = situation_report_history.report_id
          and (
              r.barangay_id = (select private.my_barangay_id())
              or (select private.has_permission('reports.view_all'))
          )
    )
);

create policy "report authors or reviewers add history"
on public.situation_report_history for insert to authenticated
with check (
    changed_by = (select auth.uid())
    and exists (
        select 1 from public.situation_reports r
        where r.report_id = situation_report_history.report_id
          and (
              r.barangay_id = (select private.my_barangay_id())
              or (select private.has_permission('reports.review'))
          )
    )
);

-- Request access is restricted to the request's barangay or authorized staff.
create policy "read permitted assistance requests"
on public.assistance_requests for select to authenticated
using (
    barangay_id = (select private.my_barangay_id())
    or (select private.has_permission('requests.review'))
    or (select private.has_role('super_admin'))
);

create policy "barangay submits own assistance requests"
on public.assistance_requests for insert to authenticated
with check (
    barangay_id = (select private.my_barangay_id())
    and requested_by = (select auth.uid())
    and (select private.has_permission('requests.submit'))
);

create policy "authorized staff update requests"
on public.assistance_requests for update to authenticated
using (
    (select private.has_permission('requests.review'))
    or (
        barangay_id = (select private.my_barangay_id())
        and requested_by = (select auth.uid())
    )
)
with check (
    (select private.has_permission('requests.review'))
    or (
        barangay_id = (select private.my_barangay_id())
        and requested_by = (select auth.uid())
    )
);

create policy "administrators delete requests"
on public.assistance_requests for delete to authenticated
using ((select private.has_role('super_admin')));

create policy "read request history"
on public.assistance_request_history for select to authenticated
using (
    exists (
        select 1 from public.assistance_requests r
        where r.request_id = assistance_request_history.request_id
          and (
              r.barangay_id = (select private.my_barangay_id())
              or (select private.has_permission('requests.review'))
          )
    )
);

create policy "authorized users add request history"
on public.assistance_request_history for insert to authenticated
with check (
    changed_by = (select auth.uid())
    and (
        (select private.has_permission('requests.review'))
        or (select private.has_permission('requests.track'))
    )
);

create policy "read request tracking"
on public.request_tracking_updates for select to authenticated
using (
    exists (
        select 1 from public.assistance_requests r
        where r.request_id = request_tracking_updates.request_id
          and (
              r.barangay_id = (select private.my_barangay_id())
              or (select private.has_permission('requests.track'))
          )
    )
);

create policy "authorized staff track requests"
on public.request_tracking_updates for insert to authenticated
with check (
    updated_by = (select auth.uid())
    and (
        (select private.has_permission('requests.track'))
        or (select private.has_permission('requests.review'))
    )
);

-- Evacuation center policies.
create policy "users view evacuation centers"
on public.evacuation_centers for select to authenticated
using (auth.uid() is not null);

create policy "authorized staff manage evacuation centers"
on public.evacuation_centers for all to authenticated
using (
    (select private.has_permission('evacuation.manage'))
    or (select private.has_role('super_admin'))
)
with check (
    (select private.has_permission('evacuation.manage'))
    or (select private.has_role('super_admin'))
);

create policy "users view occupancy snapshots"
on public.evacuation_occupancy_snapshots for select to authenticated
using (auth.uid() is not null);

create policy "authorized staff record occupancy"
on public.evacuation_occupancy_snapshots for insert to authenticated
with check (
    recorded_by = (select auth.uid())
    and (
        (select private.has_permission('evacuation.update'))
        or (select private.has_role('super_admin'))
    )
);

create policy "authorized staff manage evacuation records"
on public.evacuation_records for all to authenticated
using (
    (select private.has_permission('evacuation.manage'))
    or (select private.has_role('super_admin'))
)
with check (
    (select private.has_permission('evacuation.manage'))
    or (select private.has_role('super_admin'))
);

-- Relief stock and distribution policies.
create policy "authorized users view relief items"
on public.relief_items for select to authenticated
using (auth.uid() is not null);

create policy "relief coordinators manage items"
on public.relief_items for all to authenticated
using (
    (select private.has_permission('relief.manage_stock'))
    or (select private.has_role('super_admin'))
)
with check (
    (select private.has_permission('relief.manage_stock'))
    or (select private.has_role('super_admin'))
);

create policy "authorized users view stock locations"
on public.relief_stock_locations for select to authenticated
using (auth.uid() is not null);

create policy "relief coordinators manage stock locations"
on public.relief_stock_locations for all to authenticated
using (
    (select private.has_permission('relief.manage_stock'))
    or (select private.has_role('super_admin'))
)
with check (
    (select private.has_permission('relief.manage_stock'))
    or (select private.has_role('super_admin'))
);

create policy "authorized users view stock movements"
on public.relief_stock_movements for select to authenticated
using (
    (select private.has_permission('relief.manage_stock'))
    or (select private.has_permission('relief.distribute'))
    or (select private.has_role('super_admin'))
);

create policy "relief coordinators record stock movements"
on public.relief_stock_movements for insert to authenticated
with check (
    recorded_by = (select auth.uid())
    and (
        (select private.has_permission('relief.manage_stock'))
        or (select private.has_role('super_admin'))
    )
);

create policy "authorized users view distributions"
on public.relief_distributions for select to authenticated
using (
    barangay_id = (select private.my_barangay_id())
    or (select private.has_permission('relief.distribute'))
    or (select private.has_role('super_admin'))
);

create policy "authorized staff create distributions"
on public.relief_distributions for insert to authenticated
with check (
    prepared_by = (select auth.uid())
    and (
        (select private.has_permission('relief.distribute'))
        or (select private.has_role('super_admin'))
    )
);

create policy "authorized staff update distributions"
on public.relief_distributions for update to authenticated
using (
    (select private.has_permission('relief.distribute'))
    or (select private.has_role('super_admin'))
)
with check (
    (select private.has_permission('relief.distribute'))
    or (select private.has_role('super_admin'))
);

create policy "users view distribution items"
on public.relief_distribution_items for select to authenticated
using (
    exists (
        select 1 from public.relief_distributions d
        where d.distribution_id = relief_distribution_items.distribution_id
          and (
              d.barangay_id = (select private.my_barangay_id())
              or (select private.has_permission('relief.distribute'))
          )
    )
);

create policy "authorized staff add distribution items"
on public.relief_distribution_items for insert to authenticated
with check (
    (select private.has_permission('relief.distribute'))
    or (select private.has_role('super_admin'))
);

create policy "users view acknowledgments"
on public.distribution_acknowledgments for select to authenticated
using (
    exists (
        select 1 from public.relief_distributions d
        where d.distribution_id = distribution_acknowledgments.distribution_id
          and (
              d.barangay_id = (select private.my_barangay_id())
              or (select private.has_permission('relief.distribute'))
          )
    )
);

create policy "authorized staff record acknowledgments"
on public.distribution_acknowledgments for insert to authenticated
with check (
    (select private.has_permission('relief.distribute'))
    or (select private.has_role('super_admin'))
);

-- Notifications: only the recipient can read/update their notifications.
create policy "users read own notifications"
on public.notifications for select to authenticated
using (user_id = (select auth.uid()));

create policy "users update own notifications"
on public.notifications for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

-- Audit logs are read-only to authorized administrators.
create policy "administrators read audit logs"
on public.audit_logs for select to authenticated
using (
    (select private.has_permission('audit.view'))
    or (select private.has_role('super_admin'))
);

-- ============================================================
-- 15. IMPORTANT: VERIFY POLICIES BEFORE DEPLOYMENT
-- ============================================================

-- The schema deliberately does not grant anonymous API access.
-- Do not put a Supabase service_role key in a browser or mobile app.
-- Create Auth users first, then create user_profiles and user_roles
-- using a trusted administrator workflow.
--
-- Test that:
-- 1. A barangay reporter cannot submit for another barangay.
-- 2. A barangay reporter cannot read another barangay's reports.
-- 3. City administrators can review reports across barangays.
-- 4. Only authorized roles can approve requests and distribute relief.
-- 5. One active designated reporter is assigned per barangay.
-- 6. Report/request history cannot be altered by ordinary users.
--
-- Use Supabase SQL Editor and RLS tests before using real data.
