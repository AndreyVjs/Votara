const SUPABASE_URL = 'https://tkrcrztukmvxnmmupiia.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_-_wC62-UrSW8h49U6jxujw_rNmukFAU';

// Verifica se o script do supabase do cdn foi carregado (no head do html)
if (!window.supabase) {
    console.error("Supabase CDN script is missing.");
}

const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
window.supabaseClient = client; // alias legado
window.client = client;         // alias usado em admin.html, dashboard.html, projeto.html
