// Washington – målestokk (duplikat-scoring).
// Samme kortstokker; måler poeng/runde-differansen i samme sete mellom en
// testkonfig og en baselinekonfig. Modus styrer hva som varieres.
// bygg: g++ -O2 -std=c++17 harness.cpp -o harness && ./harness [runder] [verdener] [eksaktFra] [modus]
//   modus: pimc (PIMC-spill vs heuristikk) | weighted (vekting vs uniform) | bidsim (fri budgivning vs heuristikk)
#include "player.hpp"
#include <cstdio>
#include <cmath>
#include <string>
#include <random>
using namespace wa;

struct Cfg { PlayPolicy pol[4]; bool bidSim[4]; int nWorlds, exactFrom, nBidWorlds; };

static std::array<int,4> playRound(u64 dealSeed, int dealer, const Cfg& cfg, u64 playSeed){
    Round R(dealSeed); R.dealer=dealer;
    std::mt19937_64 prng(playSeed);
    int attempts=0; R.deal();
    while(true){
        while(R.phase==P_BID){ int s=R.activeBidder;
            int b = cfg.bidSim[s]? chooseBidSim(R,s,cfg.nBidWorlds,prng) : chooseBid(R,s);
            R.applyBid(s,b); }
        if(R.phase==P_REDEAL){ if(++attempts<8){ R.dealer=(R.dealer+1)%4; R.deal(); continue; } else { std::array<int,4> z{}; return z; } }
        break;
    }
    R.applyDiscard(chooseDiscard(R));
    auto ta=chooseTrumpAsk(R); R.applyTrump(ta.first, ta.second);
    while(R.phase==P_PLAY){ int s=R.active();
        R.applyPlay(s, choosePlay(R,s,cfg.pol[s],cfg.nWorlds,cfg.exactFrom,prng)); }
    return R.scoreDelta;
}

int main(int argc, char** argv){
    int rounds  = argc>1? atoi(argv[1]) : 400;
    int nWorlds = argc>2? atoi(argv[2]) : 24;
    int exactFrom=argc>3? atoi(argv[3]) : 5;
    std::string mode = argc>4? argv[4] : "pimc";
    int nBid = argc>5? atoi(argv[5]) : 24;

    // Per modus: (bidSim,play) for TEST-setet, for BASE-setet, og for bordet.
    bool tBid=false,bBid=false,tblBid=false; PlayPolicy tPol,bPol,tblPol;
    if(mode=="weighted"){ tPol=PIMC_WEIGHTED; bPol=PIMC_UNIFORM; tblPol=PIMC_UNIFORM; }
    else if(mode=="bidsim"){ tBid=true; bBid=false; tPol=bPol=PIMC_UNIFORM; tblPol=HEUR; }
    else { tPol=PIMC_UNIFORM; bPol=HEUR; tblPol=HEUR; }

    printf("Modus=%s  runder=%d verdener=%d eksaktFra=%d budverdener=%d\n", mode.c_str(),rounds,nWorlds,exactFrom,nBid);

    double sum=0,sum2=0; long n=0; double sT=0,sB=0;
    std::mt19937_64 seedgen(0xC0FFEE);
    for(int r=0;r<rounds;r++){
        u64 dealSeed=seedgen(); int dealer=(int)(seedgen()%4);
        for(int seat=0;seat<4;seat++){
            u64 pseed=dealSeed ^ (0x9E3779B97F4A7C15ull*(seat+1));
            Cfg ct,cb;
            for(int s=0;s<4;s++){ ct.pol[s]=tblPol; ct.bidSim[s]=tblBid; cb.pol[s]=tblPol; cb.bidSim[s]=tblBid; }
            ct.pol[seat]=tPol; ct.bidSim[seat]=tBid;
            cb.pol[seat]=bPol; cb.bidSim[seat]=bBid;
            ct.nWorlds=cb.nWorlds=nWorlds; ct.exactFrom=cb.exactFrom=exactFrom; ct.nBidWorlds=cb.nBidWorlds=nBid;
            int dt=playRound(dealSeed,dealer,ct,pseed)[seat];
            int db=playRound(dealSeed,dealer,cb,pseed)[seat];
            double diff=dt-db; sum+=diff; sum2+=diff*diff; n++; sT+=dt; sB+=db;
        }
        if((r+1)%100==0){ double m=sum/n, se=std::sqrt((sum2/n-m*m)/n);
            printf("  %d: diff=%.3f ± %.3f  (test %.2f vs base %.2f p/runde)\n", r+1,m,1.96*se,sT/n,sB/n); fflush(stdout); }
    }
    double m=sum/n, se=std::sqrt((sum2/n-m*m)/n);
    printf("\nRESULTAT: %.3f ± %.3f poeng/runde-fordel (95%% CI), n=%ld\n", m,1.96*se,n);
    printf("  test %.3f  vs  base %.3f poeng/runde\n", sT/n, sB/n);
    return 0;
}
