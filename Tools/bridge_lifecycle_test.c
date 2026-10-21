#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "advent_bridge.h"
static pthread_mutex_t m=PTHREAD_MUTEX_INITIALIZER; static pthread_cond_t c=PTHREAD_COND_INITIALIZER;
static int prompts, ended, loc, seen;
static void out(void*x,const char*t,long n){(void)x;(void)t;(void)n;}
static void pr(void*x,const char*p,const advent_snapshot_t*s){(void)x;(void)p;pthread_mutex_lock(&m);prompts++;loc=s->location;seen=0;for(int i=0;i<s->location_count;i++)seen+=s->seen[i];pthread_cond_signal(&c);pthread_mutex_unlock(&m);}
static void en(void*x,int st){(void)x;(void)st;pthread_mutex_lock(&m);ended++;pthread_cond_signal(&c);pthread_mutex_unlock(&m);}
static void waitp(void){pthread_mutex_lock(&m);while(!prompts)pthread_cond_wait(&c,&m);prompts--;pthread_mutex_unlock(&m);}
static void say(const char*s){waitp();advent_submit(s);}
int main(void){advent_set_callbacks(0,out,pr,en);advent_set_save_directory("/tmp");
 for(int round=0;round<2;round++){ advent_start(0); say("n"); say("e"); say("w"); say("s"); waitp();
  printf("round %d: loc=%d seen=%d\n",round,loc,seen);
  printf("save ok=%d\n",advent_save("/tmp/slot.adv")); advent_stop(); prompts=0; }
 ended=0; advent_start("/tmp/slot.adv"); waitp(); printf("restored: loc=%d seen=%d running=%d\n",loc,seen,advent_is_running());
 advent_submit("quit"); waitp(); advent_submit("y"); pthread_mutex_lock(&m);while(!ended)pthread_cond_wait(&c,&m);pthread_mutex_unlock(&m);
 printf("ended=%d running=%d\n",ended,advent_is_running()); advent_stop(); return 0;}
