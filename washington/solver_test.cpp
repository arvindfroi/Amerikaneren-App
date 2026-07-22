// Kryssjekk: alfa-beta-løseren = rå minimaks, + crossover-timing.
// bygg: g++ -O2 -std=c++17 solver_test.cpp -o solver_test && ./solver_test
#include "solver.hpp"
#include <cstdio>
#include <chrono>
#include <algorithm>
using namespace wa;

// Rå minimaks uten TT/reduksjon – uavhengig fasit.
static int brute(SState t){
    u64 uni=t.hands[0]|t.hands[1]|t.hands[2]|t.hands[3];
    if(uni==0) return 0;
    int seat=t.active(); bool erMaks=t.teamMask&(1<<seat);
    u64 legal=legalMask(t);
    int best=erMaks?-1:999;
    u64 rem=legal;
    while(rem){ int idx=lowest(rem); rem&=rem-1;
        SState c=t; int w=applyMove(c,idx); int val;
        if(w>=0){ int bonus=(t.teamMask&(1<<w))?1:0; val=bonus+brute(c); }
        else val=brute(c);
        if(erMaks){ if(val>best)best=val; } else { if(val<best)best=val; }
    }
    return best;
}

static SState randomState(int cardsEach,std::mt19937_64&rng){
    std::array<int,52> d; for(int i=0;i<52;i++)d[i]=i;
    for(int i=51;i>0;i--){ std::uniform_int_distribution<int> u(0,i); std::swap(d[i],d[u(rng)]); }
    SState t{}; int idx=0;
    for(int s=0;s<4;s++)for(int k=0;k<cardsEach;k++) t.hands[s]|=bit(d[idx++]);
    t.trump=(int)(rng()%5)-1; t.leader=(int)(rng()%4); t.bidWinner=(int)(rng()%4);
    t.teamMask = (1<<t.bidWinner); int mk=(t.bidWinner+1+(int)(rng()%3))%4; t.teamMask|=(1<<mk);
    t.firstTrick=false; t.plikt=-1; t.trCount=0;
    return t;
}

int main(){
    std::mt19937_64 rng(777);
    long checks=0, mism=0;
    for(int ce=2; ce<=4; ce++){
        int trials = ce<=3?400:120;
        for(int tr=0; tr<trials; tr++){
            SState t=randomState(ce,rng);
            Dobbeltdummy dd; int a=dd.solve(t), b=brute(t); checks++;
            if(a!=b){ mism++; if(mism<=5) printf("MISMATCH ce=%d ab=%d brute=%d\n",ce,a,b); }
        }
        printf("  ce=%d: %ld sjekker, %ld avvik\n", ce, checks, mism); fflush(stdout);
    }
    printf("Korrekthet: %ld/%ld OK, %ld avvik\n", checks-mism, checks, mism);

    printf("\n== crossover (median ms per solve) ==\n");
    for(int ce=4; ce<=12; ce++){
        int N = ce<=8?300:(ce<=10?40:6);
        std::vector<double> ts;
        auto t0=std::chrono::high_resolution_clock::now();
        for(int i=0;i<N;i++){ SState t=randomState(ce,rng); Dobbeltdummy dd;
            auto s0=std::chrono::high_resolution_clock::now(); dd.solve(t);
            auto s1=std::chrono::high_resolution_clock::now();
            ts.push_back(std::chrono::duration<double,std::milli>(s1-s0).count());
            if(std::chrono::duration<double>(s1-t0).count()>6.0){ N=i+1; break; }
        }
        std::sort(ts.begin(),ts.end());
        printf("  %2d kort/hand: median %8.3f ms  maks %8.1f ms  (N=%zu)\n",
               ce, ts[ts.size()/2], ts.back(), ts.size());
    }
    return mism?1:0;
}
