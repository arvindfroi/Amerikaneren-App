// Fuzz + invariant-sjekk for Washington-motoren.
// Tilfeldige lovlige spillere, tusenvis av runder. Bekrefter regellovlighet,
// stikk-/kortbevaring og at poengene følger REGLER.md.
// bygg: g++ -O2 -std=c++17 fuzz.cpp -o fuzz && ./fuzz
#include "game.hpp"
#include <cstdio>
#include <vector>
using namespace wa;

static std::vector<int> idxs(u64 m){ std::vector<int> v; while(m){ v.push_back(lowest(m)); m&=m-1; } return v; }
static int pick(u64 m, std::mt19937_64& r){ auto v=idxs(m); std::uniform_int_distribution<int> u(0,(int)v.size()-1); return v[u(r)]; }
static int pick(const std::vector<int>& v, std::mt19937_64& r){ std::uniform_int_distribution<int> u(0,(int)v.size()-1); return v[u(r)]; }

int main(){
    std::mt19937_64 rng(20260722);
    std::uniform_real_distribution<double> unit(0,1);
    long rounds=0, contracts=0, checks=0, fails=0;
    int solos=0, ameriks=0, numbers=0, made=0;

    for(long game=0; game<20000; game++){
        Round R(rng());
        R.dealer = (int)(rng()%4);
        int attempts=0;
        redeal:
        R.deal();

        // Budrunde.
        while(R.phase==P_BID){
            int s=R.activeBidder; auto lb=R.legalBids(s);
            int code;
            bool hasPass = !lb.empty() && lb[0]==BID_PASS;
            if(hasPass && unit(rng)<0.55) code=BID_PASS;
            else { std::vector<int> nz; for(int b:lb) if(b!=BID_PASS) nz.push_back(b);
                   code = nz.empty()? BID_PASS : pick(nz,rng); }
            R.applyBid(s,code);
        }
        if(R.phase==P_REDEAL){ if(++attempts<8){ R.dealer=(R.dealer+1)%4; goto redeal; } else continue; }
        rounds++; contracts++;

        // Vraking: 4 tilfeldige av budvinnerens 16.
        u64 h=R.hands[R.bidWinner], d=0; for(int k=0;k<4;k++){ int c=pick(h,rng); d|=bit(c); h&=~bit(c);}
        R.applyDiscard(d);

        // Trumf + etterlyst.
        int suit=(int)(rng()%4);
        u64 forbidden = R.hands[R.bidWinner] | R.discard;
        u64 askable = (~forbidden) & ((u64(1)<<52)-1);
        u64 askableTrump = askable & suitMask(suit);
        int ask;
        if(R.isSolo && unit(rng)<0.3) ask=-1;
        else ask = pick(askableTrump?askableTrump:askable, rng);
        R.applyTrump(suit, ask);
        if(R.isSolo) solos++; else if(R.isAmerikaner) ameriks++; else numbers++;

        // Stikkspill.
        while(R.phase==P_PLAY){
            int s=R.active(); u64 lm=R.legalPlay(s);
            if(lm==0){ printf("FEIL: ingen lovlige kort seat %d\n", s); fails++; break; }
            // lovlighet: alle valgte kort må ligge i lm (asserts fanger ellers)
            R.applyPlay(s, pick(lm,rng));
        }

        // ---- Invarianter ----
        checks++;
        int sumT=0; for(int s=0;s<4;s++) sumT+=R.tricksWon[s];
        if(sumT!=R.tricksTotal){ printf("FEIL: stikk-sum %d != %d\n",sumT,R.tricksTotal); fails++; }
        if(popcount(R.played)!=48){ printf("FEIL: spilte %d != 48\n", popcount(R.played)); fails++; }
        if(popcount(R.discard)!=4 || (R.played&R.discard)){ printf("FEIL: vrak/kortoverlapp\n"); fails++; }
        if((R.played|R.discard)!=((u64(1)<<52)-1)){ printf("FEIL: ikke alle 52 kort gjort rede for\n"); fails++; }

        // Poeng-refasit: øvrige = egne stikk; budlag etter formel.
        std::array<int,4> exp{};
        auto isTeam=[&](int s){ return s==R.bidWinner || s==R.partner; };
        int teamT=R.tricksWon[R.bidWinner]+(R.partner>=0?R.tricksWon[R.partner]:0);
        if(R.isSolo){
            bool ok=R.tricksWon[R.bidWinner]==R.tricksTotal; exp[R.bidWinner]= ok?100:-100;
            for(int s=0;s<4;s++) if(s!=R.bidWinner) exp[s]=R.tricksWon[s];
            if(ok) made++;
        } else if(R.isAmerikaner){
            bool ok=teamT==R.tricksTotal; exp[R.bidWinner]=ok?50:-50; if(R.partner>=0)exp[R.partner]=ok?25:-25;
            for(int s=0;s<4;s++) if(!isTeam(s)) exp[s]=R.tricksWon[s];
            if(ok) made++;
        } else {
            int n=R.highBid; bool ok=teamT>=n; exp[R.bidWinner]=ok?2*n:-2*n; if(R.partner>=0)exp[R.partner]=ok?n:-n;
            for(int s=0;s<4;s++) if(!isTeam(s)) exp[s]=R.tricksWon[s];
            if(ok) made++;
        }
        for(int s=0;s<4;s++) if(R.scoreDelta[s]!=exp[s]){
            printf("FEIL: poeng seat %d motor=%d fasit=%d (bud=%d solo=%d amerik=%d)\n",
                   s,R.scoreDelta[s],exp[s],R.highBid,R.isSolo,R.isAmerikaner); fails++;
        }
    }

    printf("Runder m/kontrakt: %ld  (tallbud %d, amerikaner %d, solo %d, klart %d)\n",
           rounds, numbers, ameriks, solos, made);
    printf("Invariant-sjekker: %ld,  FEIL: %ld\n", checks, fails);
    return fails? 1 : 0;
}
