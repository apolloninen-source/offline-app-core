// The "consent" Lua module: Google's consent form (User Messaging Platform)
// for ads in the EEA, UK and Switzerland. Android only; on other platforms
// the module is not registered, and core.ads starts ads without it.
//
//   consent.request(function(self, can_request_ads, error) ... end, { debug_eea = false, test_device = nil })
//   consent.can_request_ads()           -- true once ads may be requested
//   consent.privacy_options_required()  -- true where a "Privacy choices" link must be offered
//   consent.show_privacy_options(function(self, can_request_ads, error) ... end)
//   consent.reset()                     -- testing only: forget the answer

#define EXTENSION_NAME ConsentExt
#define LIB_NAME "ConsentExt"
#define MODULE_NAME "consent"

#include <dmsdk/sdk.h>

#if defined(DM_PLATFORM_ANDROID)

#include <dmsdk/dlib/android.h>
#include <stdlib.h>
#include <string.h>

extern "C" {
JNIEXPORT void JNICALL Java_offlineappcore_consent_ConsentBridge_onResult(JNIEnv* env, jclass cls, jint kind, jboolean can_request_ads, jstring error);
}

namespace dmConsent {

enum Kind { KIND_REQUEST = 0, KIND_PRIVACY_OPTIONS = 1, KIND_COUNT = 2 };

struct Result
{
    int   m_Kind;
    bool  m_CanRequestAds;
    char* m_Error;
};

static dmScript::LuaCallbackInfo* g_Callbacks[KIND_COUNT];
static dmArray<Result>            g_Queue;
static dmMutex::HMutex            g_Mutex = 0;
static bool                       g_Accept = false;

static jclass    g_Class;
static jmethodID g_Request;
static jmethodID g_CanRequestAds;
static jmethodID g_PrivacyOptionsRequired;
static jmethodID g_ShowPrivacyOptions;
static jmethodID g_Reset;

static void Push(int kind, bool can_request_ads, const char* error)
{
    Result r;
    r.m_Kind = kind;
    r.m_CanRequestAds = can_request_ads;
    r.m_Error = error ? strdup(error) : 0;
    DM_MUTEX_SCOPED_LOCK(g_Mutex);
    if (!g_Accept)
    {
        free(r.m_Error);
        return;
    }
    if (g_Queue.Full())
    {
        g_Queue.OffsetCapacity(4);
    }
    g_Queue.Push(r);
}

static void SetCallback(lua_State* L, int kind, int index)
{
    if (g_Callbacks[kind])
    {
        dmScript::DestroyCallback(g_Callbacks[kind]);
        g_Callbacks[kind] = 0;
    }
    if (lua_isfunction(L, index))
    {
        g_Callbacks[kind] = dmScript::CreateCallback(L, index);
    }
}

static void Invoke(const Result& r)
{
    dmScript::LuaCallbackInfo* cb = g_Callbacks[r.m_Kind];
    if (!dmScript::IsCallbackValid(cb))
    {
        return;
    }
    lua_State* L = dmScript::GetCallbackLuaContext(cb);
    DM_LUA_STACK_CHECK(L, 0);
    if (!dmScript::SetupCallback(cb))
    {
        return;
    }
    lua_pushboolean(L, r.m_CanRequestAds);
    if (r.m_Error)
    {
        lua_pushstring(L, r.m_Error);
    }
    else
    {
        lua_pushnil(L);
    }
    dmScript::PCall(L, 3, 0);
    dmScript::TeardownCallback(cb);
}

static jobject Activity(dmAndroid::ThreadAttacher& attacher)
{
    return attacher.GetActivity()->clazz;
}

static int Request(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    SetCallback(L, KIND_REQUEST, 1);
    bool debug_eea = false;
    const char* test_device = 0;
    if (lua_istable(L, 2))
    {
        lua_getfield(L, 2, "debug_eea");
        debug_eea = lua_toboolean(L, -1) != 0;
        lua_pop(L, 1);
        lua_getfield(L, 2, "test_device");
        test_device = lua_isstring(L, -1) ? lua_tostring(L, -1) : 0;
        // the string stays alive in the options table during this call
        lua_pop(L, 1);
    }
    dmAndroid::ThreadAttacher attacher;
    JNIEnv* env = attacher.GetEnv();
    jstring jdevice = env->NewStringUTF(test_device ? test_device : "");
    env->CallStaticVoidMethod(g_Class, g_Request, Activity(attacher), (jboolean)debug_eea, jdevice);
    env->DeleteLocalRef(jdevice);
    return 0;
}

static int CanRequestAds(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 1);
    dmAndroid::ThreadAttacher attacher;
    JNIEnv* env = attacher.GetEnv();
    lua_pushboolean(L, env->CallStaticBooleanMethod(g_Class, g_CanRequestAds, Activity(attacher)) == JNI_TRUE);
    return 1;
}

static int PrivacyOptionsRequired(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 1);
    dmAndroid::ThreadAttacher attacher;
    JNIEnv* env = attacher.GetEnv();
    lua_pushboolean(L, env->CallStaticBooleanMethod(g_Class, g_PrivacyOptionsRequired, Activity(attacher)) == JNI_TRUE);
    return 1;
}

static int ShowPrivacyOptions(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    SetCallback(L, KIND_PRIVACY_OPTIONS, 1);
    dmAndroid::ThreadAttacher attacher;
    JNIEnv* env = attacher.GetEnv();
    env->CallStaticVoidMethod(g_Class, g_ShowPrivacyOptions, Activity(attacher));
    return 0;
}

static int Reset(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    dmAndroid::ThreadAttacher attacher;
    JNIEnv* env = attacher.GetEnv();
    env->CallStaticVoidMethod(g_Class, g_Reset, Activity(attacher));
    return 0;
}

static const luaL_reg Module_methods[] =
{
    {"request", Request},
    {"can_request_ads", CanRequestAds},
    {"privacy_options_required", PrivacyOptionsRequired},
    {"show_privacy_options", ShowPrivacyOptions},
    {"reset", Reset},
    {0, 0}
};

static dmExtension::Result Initialize(dmExtension::Params* params)
{
    if (!g_Mutex)
    {
        // kept until the process ends: SDK callbacks may arrive late
        g_Mutex = dmMutex::New();
    }
    {
        DM_MUTEX_SCOPED_LOCK(g_Mutex);
        g_Accept = true;
    }
    dmAndroid::ThreadAttacher attacher;
    JNIEnv* env = attacher.GetEnv();
    jclass cls = dmAndroid::LoadClass(env, "offlineappcore.consent.ConsentBridge");
    g_Class = (jclass)env->NewGlobalRef(cls);
    g_Request = env->GetStaticMethodID(g_Class, "request", "(Landroid/app/Activity;ZLjava/lang/String;)V");
    g_CanRequestAds = env->GetStaticMethodID(g_Class, "canRequestAds", "(Landroid/app/Activity;)Z");
    g_PrivacyOptionsRequired = env->GetStaticMethodID(g_Class, "privacyOptionsRequired", "(Landroid/app/Activity;)Z");
    g_ShowPrivacyOptions = env->GetStaticMethodID(g_Class, "showPrivacyOptions", "(Landroid/app/Activity;)V");
    g_Reset = env->GetStaticMethodID(g_Class, "reset", "(Landroid/app/Activity;)V");

    lua_State* L = params->m_L;
    int top = lua_gettop(L);
    luaL_register(L, MODULE_NAME, Module_methods);
    lua_pop(L, 1);
    assert(top == lua_gettop(L));
    return dmExtension::RESULT_OK;
}

static dmExtension::Result Update(dmExtension::Params* params)
{
    dmArray<Result> pending;
    {
        DM_MUTEX_SCOPED_LOCK(g_Mutex);
        if (g_Queue.Empty())
        {
            return dmExtension::RESULT_OK;
        }
        pending.Swap(g_Queue);
    }
    for (uint32_t i = 0; i < pending.Size(); ++i)
    {
        Invoke(pending[i]);
        free(pending[i].m_Error);
    }
    return dmExtension::RESULT_OK;
}

static dmExtension::Result Finalize(dmExtension::Params* params)
{
    {
        DM_MUTEX_SCOPED_LOCK(g_Mutex);
        g_Accept = false;
        for (uint32_t i = 0; i < g_Queue.Size(); ++i)
        {
            free(g_Queue[i].m_Error);
        }
        g_Queue.SetSize(0);
    }
    for (int kind = 0; kind < KIND_COUNT; ++kind)
    {
        if (g_Callbacks[kind])
        {
            dmScript::DestroyCallback(g_Callbacks[kind]);
            g_Callbacks[kind] = 0;
        }
    }
    return dmExtension::RESULT_OK;
}

} // namespace dmConsent

JNIEXPORT void JNICALL Java_offlineappcore_consent_ConsentBridge_onResult(JNIEnv* env, jclass cls, jint kind, jboolean can_request_ads, jstring error)
{
    const char* message = error ? env->GetStringUTFChars(error, 0) : 0;
    dmConsent::Push((int)kind, can_request_ads == JNI_TRUE, message);
    if (message)
    {
        env->ReleaseStringUTFChars(error, message);
    }
}

DM_DECLARE_EXTENSION(EXTENSION_NAME, LIB_NAME, 0, 0, dmConsent::Initialize, dmConsent::Update, 0, dmConsent::Finalize)

#else

// Other platforms: no module. core.ads treats a missing `consent` as "no
// consent form needed here".
static dmExtension::Result InitializeConsent(dmExtension::Params* params) { return dmExtension::RESULT_OK; }
static dmExtension::Result FinalizeConsent(dmExtension::Params* params) { return dmExtension::RESULT_OK; }

DM_DECLARE_EXTENSION(EXTENSION_NAME, LIB_NAME, 0, 0, InitializeConsent, 0, 0, FinalizeConsent)

#endif
