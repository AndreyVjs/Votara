-- ==============================================================================
-- VOTARA — SCRIPT DE BANCO DE DADOS (SUPABASE SQL EDITOR)
-- Execute este script inteiro de uma vez. É seguro rodar mais de uma vez.
-- ==============================================================================

-- 1) Extensões
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 2) TABELA: users (espelho do auth.users)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.users (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email       TEXT NOT NULL UNIQUE,
    full_name   TEXT,
    role        TEXT DEFAULT 'student' CHECK (role IN ('admin', 'student')),
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Migração segura: renomeia 'name' para 'full_name' se ainda existir
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_name='users' AND column_name='name')
  THEN ALTER TABLE public.users RENAME COLUMN "name" TO "full_name"; END IF;
END $$;

-- ============================================================
-- 3) TABELA: courses (APIs / Projetos)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.courses (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title           TEXT NOT NULL,
    description     TEXT,
    cover_image_path TEXT,
    images          TEXT[],
    tiktok_url      TEXT,
    features        TEXT,
    pdf_file_path   TEXT,
    active          BOOLEAN DEFAULT TRUE,
    buyers_count    INTEGER DEFAULT 0,
    rating_score    NUMERIC(3,1) DEFAULT 5.0,
    api_endpoints   JSONB,
    readme_content  TEXT,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Migrações seguras: adiciona novas colunas se não existirem
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='images') THEN
    ALTER TABLE public.courses ADD COLUMN images TEXT[]; END IF;
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='tiktok_url') THEN
    ALTER TABLE public.courses ADD COLUMN tiktok_url TEXT; END IF;
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='features') THEN
    ALTER TABLE public.courses ADD COLUMN features TEXT; END IF;
  IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='courses' AND column_name='api_endpoints' AND data_type='text') THEN
    ALTER TABLE public.courses ALTER COLUMN api_endpoints TYPE JSONB USING api_endpoints::jsonb; END IF;
END $$;

-- ============================================================
-- 4) TABELA: enrollments (Acessos liberados)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.enrollments (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    course_id   UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, course_id)
);

-- ============================================================
-- 5) TABELA: bundles (Pacotes - Fase futura)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.bundles (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL,
    courses     UUID[] NOT NULL DEFAULT '{}',
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================
-- 6) FUNÇÃO: get_user_role() — evita recursão no RLS
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_role TEXT;
BEGIN
    SELECT raw_user_meta_data->>'role' INTO v_role
    FROM auth.users WHERE id = auth.uid();
    RETURN COALESCE(v_role, 'student');
END; $$;

-- ============================================================
-- 7) TRIGGER: popula public.users quando um novo usuário se cadastra
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email, full_name, role)
    VALUES (
        new.id,
        new.email,
        COALESCE(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
        COALESCE(new.raw_user_meta_data->>'role', 'student')
    ) ON CONFLICT (id) DO NOTHING;
    RETURN new;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 8) STORAGE: Buckets para upload de imagens e arquivos
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
  VALUES ('course_assets', 'course_assets', true) ON CONFLICT DO NOTHING;
INSERT INTO storage.buckets (id, name, public)
  VALUES ('course_files', 'course_files', false) ON CONFLICT DO NOTHING;

-- Política de Storage: apenas admins fazem upload / delete
DROP POLICY IF EXISTS "Admin pode fazer upload" ON storage.objects;
CREATE POLICY "Admin pode fazer upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'course_assets' AND public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "Imagens públicas são públicas" ON storage.objects;
CREATE POLICY "Imagens públicas são públicas"
  ON storage.objects FOR SELECT USING (bucket_id = 'course_assets');

DROP POLICY IF EXISTS "Admin pode deletar imagens" ON storage.objects;
CREATE POLICY "Admin pode deletar imagens"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'course_assets' AND public.get_user_role() = 'admin');

-- ============================================================
-- 9) RLS (Row Level Security)
-- ============================================================
ALTER TABLE public.users      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bundles    ENABLE ROW LEVEL SECURITY;

-- Users
DROP POLICY IF EXISTS "users: select_own"  ON public.users;
CREATE POLICY "users: select_own" ON public.users FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users: admin_all"   ON public.users;
CREATE POLICY "users: admin_all" ON public.users FOR ALL TO authenticated
  USING (public.get_user_role() = 'admin') WITH CHECK (public.get_user_role() = 'admin');

-- Courses / APIs
DROP POLICY IF EXISTS "Vitrine publica" ON public.courses;
CREATE POLICY "Vitrine publica" ON public.courses FOR SELECT USING (active = TRUE);
DROP POLICY IF EXISTS "Admin ve todos cursos" ON public.courses;
CREATE POLICY "Admin ve todos cursos" ON public.courses FOR SELECT TO authenticated USING (public.get_user_role() = 'admin');
DROP POLICY IF EXISTS "Apenas admin gerencia cursos" ON public.courses;
CREATE POLICY "Apenas admin gerencia cursos" ON public.courses FOR ALL TO authenticated
  USING (public.get_user_role() = 'admin') WITH CHECK (public.get_user_role() = 'admin');

-- Enrollments
DROP POLICY IF EXISTS "Clientes veem suas proprias compras" ON public.enrollments;
CREATE POLICY "Clientes veem suas proprias compras" ON public.enrollments FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "Apenas Admin insere/edita compras" ON public.enrollments;
CREATE POLICY "Apenas Admin insere/edita compras" ON public.enrollments FOR ALL TO authenticated
  USING (public.get_user_role() = 'admin') WITH CHECK (public.get_user_role() = 'admin');

-- Bundles
DROP POLICY IF EXISTS "Apenas admin gerencia pacotes" ON public.bundles;
CREATE POLICY "Apenas admin gerencia pacotes" ON public.bundles FOR ALL TO authenticated
  USING (public.get_user_role() = 'admin') WITH CHECK (public.get_user_role() = 'admin');
DROP POLICY IF EXISTS "Alunos visualizam pacotes" ON public.bundles;
CREATE POLICY "Alunos visualizam pacotes" ON public.bundles FOR SELECT TO authenticated USING (TRUE);

-- ============================================================
-- 10) ADMIN: Garante que sua conta tenha role 'admin'
-- ============================================================
UPDATE auth.users
  SET raw_user_meta_data = jsonb_set(COALESCE(raw_user_meta_data, '{}'::jsonb), '{role}', '"admin"')
  WHERE email = 'andreyvjs@gmail.com';

UPDATE public.users SET role = 'admin' WHERE email = 'andreyvjs@gmail.com';
