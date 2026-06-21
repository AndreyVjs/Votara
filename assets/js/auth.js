// Referência ao cliente supabase inicializado em supabase.js
const sb = window.supabaseClient;

// Funções de Autenticação
async function register(email, password, fullName) {
    try {
        const { data, error } = await sb.auth.signUp({
            email,
            password,
            options: {
                data: {
                    full_name: fullName,
                    role: 'student' // Por padrão, student
                }
            }
        });
        
        if (error) throw error;
        return { data, error: null };
    } catch (error) {
        console.error('Registration error:', error.message);
        return { data: null, error };
    }
}

async function login(email, password) {
    try {
        const { data, error } = await sb.auth.signInWithPassword({
            email,
            password
        });
        
        if (error) throw error;
        return { data, error: null };
    } catch (error) {
        console.error('Login error:', error.message);
        return { data: null, error };
    }
}

async function logout() {
    try {
        const { error } = await sb.auth.signOut();
        if (error) throw error;
        window.location.href = 'index.html';
    } catch (error) {
        console.error('Logout error:', error.message);
    }
}

async function getCurrentUser() {
    const { data: { session }, error } = await sb.auth.getSession();
    if (error || !session) return null;
    return session.user;
}

// Verifica sessão e redireciona baseado na role
async function requireAuth(requiredRole = null) {
    const user = await getCurrentUser();
    
    if (!user) {
        window.location.href = 'login.html';
        return null;
    }
    
    const role = user.user_metadata?.role || 'student';
    
    if (requiredRole && role !== requiredRole) {
        if (role === 'admin') {
            window.location.href = 'admin.html';
        } else {
            window.location.href = 'dashboard.html';
        }
        return null;
    }
    
    return { user, role };
}

// Listener global para atualizar UI quando logado/deslogado
document.addEventListener('DOMContentLoaded', async () => {
    const user = await getCurrentUser();
    
    // Atualizar botões de nav, se existirem na página atual
    const loginBtn = document.getElementById('nav-login-btn');
    const dashboardBtn = document.getElementById('nav-dashboard-btn');
    const logoutBtn = document.getElementById('nav-logout-btn');
    const adminBtn = document.getElementById('nav-admin-btn');
    
    if (user) {
        const role = user.user_metadata?.role || 'student';
        
        if (loginBtn) loginBtn.classList.add('d-none');
        if (dashboardBtn && role !== 'admin') dashboardBtn.classList.remove('d-none');
        if (adminBtn && role === 'admin') adminBtn.classList.remove('d-none');
        if (logoutBtn) {
            logoutBtn.classList.remove('d-none');
            logoutBtn.addEventListener('click', (e) => {
                e.preventDefault();
                logout();
            });
        }
    } else {
        // Não está logado
        if (loginBtn) loginBtn.classList.remove('d-none');
        if (dashboardBtn) dashboardBtn.classList.add('d-none');
        if (adminBtn) adminBtn.classList.add('d-none');
        if (logoutBtn) logoutBtn.classList.add('d-none');
    }
});

// Expondo globalmente para uso nas páginas
window.auth = { register, login, logout, getCurrentUser, requireAuth };
