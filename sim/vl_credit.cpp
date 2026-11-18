// Coin/start timing on the traced board (FPGA cell models), through Verilator.
// Usage: Vvl_credit <script>   script = comma list of  c<ms> (coin held), s<ms> (start
// held), w<ms> (wait), b<ms> (coin and start both held), g<ms> (wait for game over, at most ms). Prints every state change.
// Then: boot wait ms, reset clocks, PROM stream, and 1 to use the button conditioner.
#include "Vvl_credit.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
static Vvl_credit *t;
static double now_ms=0;
double sc_time_stamp(){ return now_ms; }
static const double MS_PER_CLK=1e3/115151515.0;
static unsigned last=~0u;
static void show(const char*why){
  printf("%8.1fms %-6s coin=%d start=%d EGME=%d E2PL=%d ESGB=%d ESGC=%d ECDB=%d ECDG=%d STAA=%d STGO=%d timer=%02x\n",
   now_ms,why,t->coin,t->start,t->egme,t->e2pl,t->esgb,t->esgc,t->ecdb,t->ecdg,t->staa,t->stgo,t->timer);
}
static bool until_over=false;
static void run_ms(double ms){
  long long n=(long long)(ms/MS_PER_CLK);
  for(long long i=0;i<n;i++){
    t->clk=0; t->eval(); t->clk=1; t->eval();
    if((i&4095)==0){
      now_ms+=4096*MS_PER_CLK;
      unsigned s=t->egme|t->e2pl<<1|t->esgb<<2|t->esgc<<3|t->ecdg<<4|t->stgo<<5|(t->timer==0)<<6|t->ecdb<<7|t->coin<<8|t->start<<9;
      if(s!=last){ last=s; show(""); }
      if(until_over && !t->egme) return;
    }
  }
}
int main(int argc,char**argv){
  setvbuf(stdout,NULL,_IOLBF,0);
  t=new Vvl_credit;
  t->reset=1; t->coin=0; t->start=0; t->cond=argc>5&&atoi(argv[5]);
  for(int i=0,n=argc>3?atoi(argv[3]):1;i<n;i++){ t->clk=0; t->eval(); t->clk=1; t->eval(); }
  t->reset=0;
  // PROMs through the MiSTer byte stream, as tb_game: build/rom_dr.hex or rom_derby.hex.
  { const char*rom=argc>4?argv[4]:"build/rom_dr.hex"; FILE*f=fopen(rom,"r");
    if(!f){ fprintf(stderr,"no %s\n",rom); return 1; }
    unsigned v; int a=0;
    while(fscanf(f,"%x",&v)==1){
      if(a==0) t->game_dr=v&1;
      t->prom_addr=a++; t->prom_din=v; t->prom_wr=1; t->clk=0; t->eval(); t->clk=1; t->eval();
    }
    t->prom_wr=0; fclose(f); }
  run_ms(argc>2?atof(argv[2]):1500);
  char *script=strdup(argc>1?argv[1]:"c100,w300,s100,w500");
  for(char*tok=strtok(script,",");tok;tok=strtok(NULL,",")){
    double ms=atof(tok+1);
    t->coin=(tok[0]=='c'||tok[0]=='b'); t->start=(tok[0]=='s'||tok[0]=='b');
    until_over=tok[0]=='g';
    run_ms(ms);
  }
  t->coin=0; t->start=0; show("end");
  printf("RESULT EGME=%d E2PL=%d ESGC=%d timer=%02x\n",t->egme,t->e2pl,t->esgc,t->timer);
  return 0;
}
