// Washington – dobbeltdummy-optimalitet for kortspillet, per kort-igjen-nivå.
// Selvspill (PIMC alle seter, felles heuristisk bud/vrak/trumf). For hvert
// kortvalg med ≤ grense kort: løs sann stilling eksakt, sammenlign med botens
// kort. Rask C++-løser → kan måle HELT opp til 12 kort (åpningen), som Swift
// ikke rekker. Måler effekten av endringer i grådig-åpningspolicyen.
// bygg: g++ -O2 -mbmi2 -std=c++17 optimalitet.cpp -o optimalitet
#include "player.hpp"
#include <cstdio>
#include <cmath>
using namespace wa;

static SState trueState(const Round& R, int seat){
    SState t{}; t.hands=R.hands;
    t.leader=R.trick.empty()? R.leader : R.trick.front().first;
    t.trump=R.trump; t.bidWinner=R.bidWinner; t.firstTrick=(R.trickNum==0);
    t.plikt=R.requestedPlayed? -1 : R.askedCard;
    t.teamMask=(uint8_t)(1<<R.bidWinner); if(!R.isSolo && R.partner>=0) t.teamMask|=(1<<R.partner);
    t.trCount=0; for(auto&p:R.trick){ t.trSeat[t.trCount]=p.first; t.trCard[t.trCount]=p.second; t.trCount++; }
    return t;
}

int main(int argc, char** argv){
    int rounds = argc>1? atoi(argv[1]) : 40;
    int grense = argc>2? atoi(argv[2]) : 10;
    int nWorlds= argc>3? atoi(argv[3]) : 20;
    int exactFrom = 4;
    std::mt19937_64 seedgen(0xA11CE);
    long beslNivå[14]={0}, optNivå[14]={0}, feilNivå[14]={0};
    long total=0, opt=0, feil=0;

    for(int r=0;r<rounds;r++){
        Round R(seedgen()); R.dealer=(int)(seedgen()%4);
        std::mt19937_64 prng(seedgen());
        int att=0; R.deal();
        while(true){
            while(R.phase==P_BID){ int s=R.activeBidder; R.applyBid(s, chooseBid(R,s)); }
            if(R.phase==P_REDEAL){ if(++att<8){ R.dealer=(R.dealer+1)%4; R.deal(); continue; } else break; }
            break;
        }
        if(R.phase!=P_DISCARD) continue;
        R.applyDiscard(chooseDiscard(R));
        auto ta=chooseTrumpAsk(R); R.applyTrump(ta.first, ta.second);
        while(R.phase==P_PLAY){
            int s=R.active();
            int card = choosePlay(R,s,PIMC_UNIFORM,nWorlds,exactFrom,prng);
            int igjen = popcount(R.hands[s]);
            if(igjen<=grense && igjen>=2){
                SState t=trueState(R,s);
                Dobbeltdummy d1; int o=d1.solve(t);
                SState c=t; int w=applyMove(c, /*card index*/ card);
                int bonus=(w>=0 && (t.teamMask&(1<<w)))?1:0;
                Dobbeltdummy d2; int after=bonus+d2.solve(c);
                int e=std::abs(o-after);
                total++; feil+=e; beslNivå[igjen]++; feilNivå[igjen]+=e;
                if(e==0){ opt++; optNivå[igjen]++; }
            }
            R.applyPlay(s, card);
        }
        if((r+1)%10==0){ printf("  ..%d runder, %ld beslutninger\n", r+1, total); fflush(stdout); }
    }
    printf("== Dobbeltdummy-optimalitet (C++ PIMC, ≤%d kort) ==\n", grense);
    printf("  %ld beslutninger | %.1f %% optimale | snittfeil %.4f stikk\n",
           total, 100.0*opt/std::max(1L,total), (double)feil/std::max(1L,total));
    printf("  per kort-igjen (åpning → sluttspill):\n");
    for(int n=13;n>=2;n--) if(beslNivå[n]>0)
        printf("    %2d kort: %.1f %% optimale, snittfeil %.3f  (n=%ld)\n",
               n, 100.0*optNivå[n]/beslNivå[n], (double)feilNivå[n]/beslNivå[n], beslNivå[n]);
    return 0;
}
