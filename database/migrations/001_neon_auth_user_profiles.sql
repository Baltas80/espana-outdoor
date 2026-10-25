-- Ejecutar en Neon SQL Editor DESPUÉS de habilitar Neon Data API
-- con Neon Auth para la rama de producción.
-- Los usuarios solo pueden leer y modificar la fila cuyo user_id coincide
-- con auth.user_id() del JWT validado por Neon Data API.

BEGIN;

CREATE TABLE IF NOT EXISTS public.user_profiles (
  user_id TEXT PRIMARY KEY DEFAULT (auth.user_id()),
  display_name VARCHAR(50) NOT NULL
    CHECK (char_length(display_name) BETWEEN 2 AND 50),
  username VARCHAR(20) NOT NULL UNIQUE
    CHECK (username ~ '^[a-z0-9][a-z0-9._-]{2,19}

-- Añade la foto a las instalaciones existentes sin borrar los perfiles guardados.
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS avatar_data TEXT NOT NULL DEFAULT '';

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_photos FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.user_profiles FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.user_profiles TO authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE public.user_photos TO authenticated;

DROP POLICY IF EXISTS user_profiles_select_own ON public.user_profiles;
CREATE POLICY user_profiles_select_own
  ON public.user_profiles
  FOR SELECT TO authenticated
  USING ((SELECT auth.user_id()) = user_id);

DROP POLICY IF EXISTS user_profiles_insert_own ON public.user_profiles;
CREATE POLICY user_profiles_insert_own
  ON public.user_profiles
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.user_id()) = user_id);

DROP POLICY IF EXISTS user_profiles_update_own ON public.user_profiles;
CREATE POLICY user_profiles_update_own
  ON public.user_profiles
  FOR UPDATE TO authenticated
  USING ((SELECT auth.user_id()) = user_id)
  WITH CHECK ((SELECT auth.user_id()) = user_id);

DROP POLICY IF EXISTS user_photos_select_own ON public.user_photos;
CREATE POLICY user_photos_select_own
  ON public.user_photos
  FOR SELECT TO authenticated
  USING ((SELECT auth.user_id()) = user_id);

DROP POLICY IF EXISTS user_photos_insert_own ON public.user_photos;
CREATE POLICY user_photos_insert_own
  ON public.user_photos
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.user_id()) = user_id);

DROP POLICY IF EXISTS user_photos_delete_own ON public.user_photos;
CREATE POLICY user_photos_delete_own
  ON public.user_photos
  FOR DELETE TO authenticated
  USING ((SELECT auth.user_id()) = user_id);

COMMIT;
),
  home_area VARCHAR(80) NOT NULL DEFAULT '',
  bio VARCHAR(160) NOT NULL DEFAULT '',
  avatar_data TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Galería privada: cada fotografía pertenece al usuario autenticado.
-- Las imágenes se optimizan en el navegador antes de enviarse.
CREATE TABLE IF NOT EXISTS public.user_photos (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id TEXT NOT NULL DEFAULT (auth.user_id()),
  image_data TEXT NOT NULL
    CHECK (char_length(image_data) <= 420000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_photos_owner_created_idx
  ON public.user_photos (user_id, created_at DESC);

-- Añade la foto a las instalaciones existentes sin borrar los perfiles guardados.
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS avatar_data TEXT NOT NULL DEFAULT '';

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.user_profiles FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.user_profiles TO authenticated;

DROP POLICY IF EXISTS user_profiles_select_own ON public.user_profiles;
CREATE POLICY user_profiles_select_own
  ON public.user_profiles
  FOR SELECT TO authenticated
  USING ((SELECT auth.user_id()) = user_id);

DROP POLICY IF EXISTS user_profiles_insert_own ON public.user_profiles;
CREATE POLICY user_profiles_insert_own
  ON public.user_profiles
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.user_id()) = user_id);

DROP POLICY IF EXISTS user_profiles_update_own ON public.user_profiles;
CREATE POLICY user_profiles_update_own
  ON public.user_profiles
  FOR UPDATE TO authenticated
  USING ((SELECT auth.user_id()) = user_id)
  WITH CHECK ((SELECT auth.user_id()) = user_id);

COMMIT;
