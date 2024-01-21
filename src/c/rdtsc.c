unsigned long long rdtsc(void)
{
  unsigned int lo, hi;
  __asm__ __volatile__("mfence");
  __asm__ __volatile__("rdtsc"
                       : "=a"(lo), "=d"(hi));
  __asm__ __volatile__("mfence");
  return ((unsigned long long)hi << 32) | lo;
}
