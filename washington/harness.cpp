// Washington – målestokk (duplikat-scoring).
// Samme kortstokker; bud/vrak/trumf er lik heuristikk for alle seter, så bare
// kortspill-policyen skiller. Måler poeng/runde-differansen i samme sete.
// bygg: g++ -O2 -std=c++17 harness.cpp -o harness && ./harness
#include "player.hpp"
#include <cstdio>
#include <cmath>
#include <random>
using namespace wa;

struct Cfg { PlayPolicy pol[4]; int nWorlds, exactFrom; };

// Spiller én runde med gitt kortstokk-frø. Bud/vrak/trumf: felles heuristikk.
static std::array<int,4> playRound(u64 dealSeed, int dealer, const Cfg& cfg, u64 playSeed){
    Round R(dealSeed); R.dealer=dealer;
    std::mt19937_64 prng(playSeed);
    int attempts=0;
    R.deal();
    while(true){
        while(R.phase==P_BID){ int s=R.activeBidder; R.applyBid(s, chooseBid(R,s)); }
        if(R.phase==P_REDEAL){ if(++attempts<8){ R.dealer=(R.dealer+1)%4; R.deal(); continue; } else { std::array<int,4> z{}; return z; } }
        break;
    }
    R.applyDiscard(chooseDiscard(R));
    auto ta=chooseTrumpAsk(R); R.applyTrump(ta.first, ta.second);
    while(R.phase==P_PLAY){ int s=R.active();
        int card=choosePlay(R,s,cfg.pol[s],cfg.nWorlds,cfg.exactFrom,prng);
        R.applyPlay(s,card);
    }
    return R.scoreDelta;
}

int main(int argc, char** argv){
    int rounds = argc>1? atoi(argv[1]) : 400;
    int nWorlds= argc>2? atoi(argv[2]) : 20;
    int exactFrom= argc>3? atoi(argv[3]) : 4;
    PlayPolicy TEST = PIMC_UNIFORM;
    if(argc>4 && std::string(argv[4])=="weighted") TEST=PIMC_WEIGHTED;

    // Baseline for TEST: motstanderen i samme sete er alltid PIMC_UNIFORM når vi
    // tester WEIGHTED (så vi isolerer vektingen), ellers HEUR.
    PlayPolicy BASE = (TEST==PIMC_WEIGHTED)? PIMC_UNIFORM : HEUR;
    // Bordet rundt testsetet: HEUR for uniform-test, PIMC_UNIFORM for vektet-test.
    PlayPolicy TABLE = (TEST==PIMC_WEIGHTED)? PIMC_UNIFORM : HEUR;

    printf("Test=%s vs Base=%s  (bord=%s)  runder=%d verdener=%d eksaktFra=%d\n",
        TEST==PIMC_WEIGHTED?"WEIGHTED":"PIMC", BASE==PIMC_UNIFORM?"PIMC":"HEUR",
        TABLE==PIMC_UNIFORM?"PIMC":"HEUR", rounds, nWorlds, exactFrom);

    double sum=0, sum2=0; long n=0; double sT=0,sB=0;
    std::mt19937_64 seedgen(0xC0FFEE);
    for(int r=0;r<rounds;r++){
        u64 dealSeed=seedgen(); int dealer=(int)(seedgen()%4);
        for(int seat=0;seat<4;seat++){
            u64 pseed = dealSeed ^ (0x9E3779B97F4A7C15ull*(seat+1));
            Cfg ct; for(int s=0;s<4;s++) ct.pol[s]=TABLE; ct.pol[seat]=TEST; ct.nWorlds=nWorlds; ct.exactFrom=exactFrom;
            Cfg cb; for(int s=0;s<4;s++) cb.pol[s]=TABLE; cb.pol[seat]=BASE; cb.nWorlds=nWorlds; cb.exactFrom=exactFrom;
            int dt=playRound(dealSeed,dealer,ct,pseed)[seat];
            int db=playRound(dealSeed,dealer,cb,pseed)[seat];
            double diff=dt-db; sum+=diff; sum2+=diff*diff; n++; sT+=dt; sB+=db;
        }
        if((r+1)%100==0){ double mean=sum/n, se=std::sqrt((sum2/n-mean*mean)/n);
            printf("  %d runder: diff=%.3f ± %.3f  (test %.2f vs base %.2f p/runde)\n",
                   r+1, mean, 1.96*se, sT/n, sB/n); fflush(stdout); }
    }
    double mean=sum/n, se=std::sqrt((sum2/n-mean*mean)/n);
    printf("\nRESULTAT: %.3f ± %.3f poeng/runde-fordel (95%% CI), n=%ld\n", mean, 1.96*se, n);
    printf("  test %.3f  vs  base %.3f poeng/runde\n", sT/n, sB/n);
    return 0;
}
