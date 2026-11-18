// Where the four cars start, on the traced board (FPGA cell models), through Verilator.
// Usage: Vvl_spawn <rom.hex> <reset clocks> <script> [pgm prefix]
//   script = comma list of  c<ms> coin held, s<ms> start held, w<ms> wait,
//            g<ms> wait with both pedals down, p (save the next whole frame as PGM).
// Prints the position counters when a car is preset (5APRS, 5CPRS, 5ECDG) and at the
// end of each script step, and counts frames where both enemies share position and heading.
#include "Vvl_spawn.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
static Vvl_spawn *t;
static double now_ms=0;
double sc_time_stamp(){ return now_ms; }
static const double MS_PER_CLK=1e3/115151515.0;
static const int W=912,H=288;
static std::vector<unsigned char> fb(W*H,0);
static int x=0,y=0,frames=0,stacked=0,counted=0,want_pgm=0,shots=0;
static bool old_x=0,old_hs=0,old_vs=0,old_a=1,old_c=1;
static const char*prefix=0;
static void pos(const char*why){
  printf("%9.1fms f%-4d %-8s A x=%02x y=%02x h=%x | C x=%02x y=%02x h=%x | P1 x=%02x y=%02x | P2 x=%02x y=%02x | game=%d p2=%d\n",
   now_ms,frames,why,t->ax,t->ay,t->ah,t->cx,t->cy,t->ch,t->mx,t->my,t->nx,t->ny,t->egme,t->e2pl);
}
static void tick(){
  t->clk=0; t->eval(); t->clk=1; t->eval(); now_ms+=MS_PER_CLK;
  if(t->xtal_o && !old_x){
    if(t->hs && !old_hs){ x=0; y++; }
    old_hs=t->hs;
    if(x<W && y<H) fb[y*W+x]=(t->hb|t->vb) ? 40 : !t->white ? 0 : t->grey ? 255 : 136;
    x++;
    if(t->vs && !old_vs){
      frames++;
      if(t->egme){ counted++; if(t->ax==t->cx && t->ay==t->cy && t->ah==t->ch) stacked++; }
      if(want_pgm==1 && prefix){
        char name[256]; snprintf(name,sizeof name,"%s_%d.pgm",prefix,shots++);
        FILE*f=fopen(name,"wb"); fprintf(f,"P5\n%d %d\n255\n",W,H); fwrite(fb.data(),1,W*H,f); fclose(f);
        printf("%9.1fms f%-4d wrote %s\n",now_ms,frames,name);
      }
      if(want_pgm) want_pgm--;
      y=0;
    }
    old_vs=t->vs;
  }
  old_x=t->xtal_o;
  // The cars' position right after each preset is released.
  if(t->aprs_n && !old_a) pos("A preset");
  if(t->cprs_n && !old_c) pos("C preset");
  old_a=t->aprs_n; old_c=t->cprs_n;
}
static void run_ms(double ms){ for(long long n=(long long)(ms/MS_PER_CLK);n>0;n--) tick(); }
int main(int argc,char**argv){
  setvbuf(stdout,NULL,_IOLBF,0);
  if(argc<4){ fprintf(stderr,"usage: Vvl_spawn rom.hex reset_clocks script [pgm prefix]\n"); return 2; }
  prefix=argc>4?argv[4]:0;
  t=new Vvl_spawn;
  t->reset=1; t->coin=0; t->start=0; t->gas1=0; t->gas2=0; t->prom_wr=0;
  for(int i=0,n=atoi(argv[2]);i<n;i++){ t->clk=0; t->eval(); t->clk=1; t->eval(); }
  { FILE*f=fopen(argv[1],"r"); if(!f){ fprintf(stderr,"no %s\n",argv[1]); return 1; }
    unsigned v; int a=0;
    while(fscanf(f,"%x",&v)==1){
      if(a==0) t->game_dr=v&1;
      t->prom_addr=a++; t->prom_din=v; t->prom_wr=1; t->clk=0; t->eval(); t->clk=1; t->eval();
    }
    t->prom_wr=0; fclose(f); }
  t->reset=0;
  char *script=strdup(argv[3]);
  for(char*tok=strtok(script,",");tok;tok=strtok(NULL,",")){
    if(tok[0]=='p'){ want_pgm=2; continue; }
    t->coin=tok[0]=='c'; t->start=tok[0]=='s';
    t->gas1=t->gas2=tok[0]=='g'?3:0;
    run_ms(atof(tok+1));
    pos(tok);
  }
  printf("RESULT game frames=%d stacked=%d\n",counted,stacked);
  return 0;
}
