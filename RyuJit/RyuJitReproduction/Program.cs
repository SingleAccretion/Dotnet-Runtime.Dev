#pragma warning disable

using System;
using System.Reflection;
using System.Runtime.CompilerServices;

namespace RyuJitReproduction
{
    public unsafe class Program
    {
        private static void Main()
        {
            var flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static;

            var type = typeof(Program);
            var method = type.GetMethod("Problem", flags);

            RuntimeHelpers.PrepareMethod(method.MethodHandle);
        }

        [ModuleInitializer]
        public static void Init() => RuntimeHelpers.RunClassConstructor(typeof(Program).TypeHandle);

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void Problem()
        {
        }
    }
}
