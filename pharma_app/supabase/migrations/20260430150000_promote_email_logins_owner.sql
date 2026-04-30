UPDATE public.profiles p
SET role = 'owner'
FROM auth.users u
WHERE u.id = p.id
  AND p.role = 'admin'
  AND u.email IS NOT NULL
  AND u.email NOT ILIKE '%@%.staff.internal';
