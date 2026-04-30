UPDATE public.profiles p
SET role = 'owner'
FROM public.teams t
WHERE p.id = t.created_by
  AND p.team_id = t.id
  AND p.role = 'admin'
  AND NOT EXISTS (
    SELECT 1
    FROM public.profiles po
    WHERE po.team_id = t.id
      AND po.role = 'owner'
  );
