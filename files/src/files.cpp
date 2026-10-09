// The "filepicker" Lua module: the phone's own file picker, to read a file
// the player chooses (a backup saved to Files, Drive or Downloads). Android
// only; on other platforms the module is not registered.
//
//   filepicker.open(function(self, text, error) ... end)
//   -- text: the file's contents (nil on error); error: nil, "cancelled" or a message

#define EXTENSION_NAME FilesExt
#define LIB_NAME "FilesExt"
#define MODULE_NAME "filepicker"

#include <dmsdk/sdk.h>

#if defined(DM_PLATFORM_ANDROID)

#include <dmsdk/dlib/android.h>
#include <stdlib.h>
#include <string.h>

extern "C" {
JNIEXPORT void JNICALL Java_offlineappcore_files_PickActivity_onResult(JNIEnv* env, jclass cls, jbyteArray data, jstring error);
}

namespace dmFiles {

struct Result
{
    char*    m_Text;
    uint32_t m_Length;
    char*    m_Error;
};

static dmScript::LuaCallbackInfo* g_Callback = 0;
static dmArray<Result>            g_Queue;
static dmMutex::HMutex            g_Mutex = 0;
static bool                       g_Accept = false;
static jclass                     g_Class;
static jmethodID                  g_Open;

static char* Copy(JNIEnv* env, jstring s)
{
    if (!s)
    {
        return 0;
    }
    const char* chars = env->GetStringUTFChars(s, 0);
    char* out = strdup(chars);
    env->ReleaseStringUTFChars(s, chars);
    return out;
}

static void FreeResult(Result& r)
{
    free(r.m_Text);
    free(r.m_Error);
    r.m_Text = r.m_Error = 0;
    r.m_Length = 0;
}

static int Open(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    luaL_checktype(L, 1, LUA_TFUNCTION);
    if (g_Callback)
    {
        dmScript::DestroyCallback(g_Callback);
    }
    g_Callback = dmScript::CreateCallback(L, 1);
    dmAndroid::ThreadAttacher attacher;
    JNIEnv* env = attacher.GetEnv();
    env->CallStaticVoidMethod(g_Class, g_Open, attacher.GetActivity()->clazz);
    return 0;
}

static const luaL_reg Module_methods[] =
{
    {"open", Open},
    {0, 0}
};

static dmExtension::Result Initialize(dmExtension::Params* params)
{
    if (!g_Mutex)
    {
        g_Mutex = dmMutex::New();
    }
    {
        DM_MUTEX_SCOPED_LOCK(g_Mutex);
        g_Accept = true;
    }
    dmAndroid::ThreadAttacher attacher;
    JNIEnv* env = attacher.GetEnv();
    jclass cls = dmAndroid::LoadClass(env, "offlineappcore.files.PickActivity");
    g_Class = (jclass)env->NewGlobalRef(cls);
    g_Open = env->GetStaticMethodID(g_Class, "open", "(Landroid/app/Activity;)V");

    lua_State* L = params->m_L;
    int top = lua_gettop(L);
    luaL_register(L, MODULE_NAME, Module_methods);
    lua_pop(L, 1);
    assert(top == lua_gettop(L));
    return dmExtension::RESULT_OK;
}

static void Invoke(Result& r)
{
    if (!dmScript::IsCallbackValid(g_Callback))
    {
        return;
    }
    lua_State* L = dmScript::GetCallbackLuaContext(g_Callback);
    DM_LUA_STACK_CHECK(L, 0);
    if (!dmScript::SetupCallback(g_Callback))
    {
        return;
    }
    if (r.m_Text)
    {
        lua_pushlstring(L, r.m_Text, r.m_Length);
    }
    else
    {
        lua_pushnil(L);
    }
    if (r.m_Error)
    {
        lua_pushstring(L, r.m_Error);
    }
    else
    {
        lua_pushnil(L);
    }
    dmScript::PCall(L, 3, 0);
    dmScript::TeardownCallback(g_Callback);
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
        FreeResult(pending[i]);
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
            FreeResult(g_Queue[i]);
        }
        g_Queue.SetSize(0);
    }
    if (g_Callback)
    {
        dmScript::DestroyCallback(g_Callback);
        g_Callback = 0;
    }
    return dmExtension::RESULT_OK;
}

} // namespace dmFiles

JNIEXPORT void JNICALL Java_offlineappcore_files_PickActivity_onResult(JNIEnv* env, jclass cls, jbyteArray data, jstring error)
{
    dmFiles::Result r;
    r.m_Text = 0;
    r.m_Length = 0;
    if (data)
    {
        jsize n = env->GetArrayLength(data);
        r.m_Text = (char*)malloc(n + 1);
        env->GetByteArrayRegion(data, 0, n, (jbyte*)r.m_Text);
        r.m_Text[n] = 0;
        r.m_Length = (uint32_t)n;
    }
    r.m_Error = dmFiles::Copy(env, error);
    DM_MUTEX_SCOPED_LOCK(dmFiles::g_Mutex);
    if (!dmFiles::g_Accept)
    {
        dmFiles::FreeResult(r);
        return;
    }
    if (dmFiles::g_Queue.Full())
    {
        dmFiles::g_Queue.OffsetCapacity(2);
    }
    dmFiles::g_Queue.Push(r);
}

DM_DECLARE_EXTENSION(EXTENSION_NAME, LIB_NAME, 0, 0, dmFiles::Initialize, dmFiles::Update, 0, dmFiles::Finalize)

#else

static dmExtension::Result InitializeFiles(dmExtension::Params* params) { return dmExtension::RESULT_OK; }
static dmExtension::Result FinalizeFiles(dmExtension::Params* params) { return dmExtension::RESULT_OK; }

DM_DECLARE_EXTENSION(EXTENSION_NAME, LIB_NAME, 0, 0, InitializeFiles, 0, 0, FinalizeFiles)

#endif
