-- Ilili Pharmacy: fix reversed name (brand) / generic_name fields.
-- Team: 4112ac1c-0ae5-436d-9036-d6b168f93cc6 (Ilili only)
-- Backup: scripts/data-backups/ilili_medicines_pre_name_swap_20260706.json
-- Rollback: scripts/data-backups/ilili_medicines_rollback_20260706.sql

WITH ilili AS (
  SELECT
    id,
    name,
    generic_name,
    CASE
      WHEN generic_name IS NULL THEN 'skip'
      WHEN lower(trim(name)) = lower(trim(generic_name)) THEN 'skip'
      WHEN name ~* '^(AMTAS|INDOMICIN|Fortine|Klamoks|oberem)$' THEN 'skip'
      WHEN name ~* '^Klamoks ' THEN 'skip'
      WHEN lower(trim(name)) IN ('oberem') AND generic_name ~* 'ondasetron' THEN 'skip'
      WHEN lower(name) ~ lower(generic_name)
        AND name ~* '(clotrimazole|ketoconazole|multivitamin|tetracycline)' THEN 'skip'
      WHEN name ~* 'Beprosone' AND generic_name ~* 'Beprosone' THEN 'skip'
      WHEN name ~* '(tablet|tab|capsule|cap|susp|syrup|injection|cream|gel|mg|ml|ointment|drops|supp|sachet|shampoo|lotion|sodium|potassium|acid|hydrochloride|phosphate|oral|film coated|bp|usp|%)'
        AND generic_name !~* '(benzoic|salicylic|amoxicillin clavulanic|amoxillin \+clavulanic)'
        THEN 'swap'
      WHEN length(trim(name)) < 40
        AND name !~* '(tablet|tab|capsule|cap|susp|syrup|injection|cream|gel|mg|ml|%)'
        AND generic_name ~* '(tablet|tab|capsule|cap|susp|syrup|injection|cream|gel|mg|ml|%)'
        THEN 'swap'
      WHEN length(trim(name)) < 30
        AND name !~* '(tablet|tab|capsule|cap|susp|syrup|injection|cream|gel|mg|ml)'
        AND generic_name !~* '(tablet|tab|capsule|cap|susp|syrup|injection|cream|gel|mg|ml|acid|sodium|potassium)'
        AND name ~* '[a-z]'
        THEN 'swap'
      ELSE 'skip'
    END AS swap_action
  FROM medicines
  WHERE team_id = '4112ac1c-0ae5-436d-9036-d6b168f93cc6'
    AND is_active = true
)
UPDATE medicines AS m
SET
  name = c.generic_name,
  generic_name = c.name
FROM ilili AS c
WHERE m.id = c.id
  AND c.swap_action = 'swap';
