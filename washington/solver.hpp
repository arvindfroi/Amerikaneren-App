// Washington – eksakt dobbeltdummy-løser (perfekt informasjon).
// Port av MesterAIs verifiserte MesterSolver (alfa-beta + transposisjon +
// sekvensreduksjon), inkl. detaljen at kort i pågående stikk teller med i
// ekvivalensen. Returnerer budgiverlagets stikk under optimalt spill.
#pragma once
#include "game.hpp"
#include <unordered_map>
#include <array>
#include <immintrin.h>
namespace wa {

struct SState {
    std::array<u64,4> hands;
    std::array<int,4> trSeat, trCard;
    int trCount=0;
    int leader=0;
    int trump=-1;
    uint8_t teamMask=0;   // budgiverlagets seter
    int bidWinner=0;
    int plikt=-1;         // etterlyst kort, håndheves i første stikk
    bool firstTrick=false;

    int active() const { return (leader + trCount) & 3; }
};

static inline bool sbeats(int c,int best,int trump){
    int sc=suitOf(c), sb=suitOf(best);
    if(sc==sb) return rankOf(c)>rankOf(best);
    return sc==trump;
}

static inline u64 legalMask(const SState& t){
    int seat=t.active(); u64 hand=t.hands[seat], m=hand;
    if(t.trCount>0){
        int led=suitOf(t.trCard[0]); u64 f=hand&suitMask(led); if(f) m=f;
    } else if(t.firstTrick && seat==t.bidWinner && t.trump>=0){
        u64 tr=hand&suitMask(t.trump); if(tr) m=tr;    // utspillsplikt
    }
    if(t.firstTrick && t.plikt>=0 && seat!=t.bidWinner && (m&bit(t.plikt)))
        return bit(t.plikt);                            // makkerplikt
    return m;
}

// Sekvensreduksjon: behold høyeste representant i hver egen «run» blant
// kortene som fortsatt er i spill (union inkluderer pågående stikk).
static inline void reducedMoves(u64 legal, u64 unionAll, int out[], int& n){
    n=0;
    for(int farge=0;farge<4;farge++){
        u64 fm=suitMask(farge); if((legal&fm)==0) continue;
        u64 u=unionAll&fm; bool prevMine=false;
        while(u){ int idx=highest(u); u&=~bit(idx);
            if(legal&bit(idx)){ if(!prevMine) out[n++]=idx; prevMine=true; }
            else prevMine=false;
        }
    }
}

// utfør: legg kort; fullfør stikk ved fjerdemann. Returnerer vinnersete el. -1.
static inline int applyMove(SState& t,int idx){
    int seat=t.active();
    t.hands[seat]&=~bit(idx);
    t.trSeat[t.trCount]=seat; t.trCard[t.trCount]=idx; t.trCount++;
    if(t.trCount<4) return -1;
    int bestSeat=t.trSeat[0], bestCard=t.trCard[0];
    for(int i=1;i<4;i++) if(sbeats(t.trCard[i],bestCard,t.trump)){ bestSeat=t.trSeat[i]; bestCard=t.trCard[i]; }
    t.leader=bestSeat; t.trCount=0; t.firstTrick=false; t.plikt=-1;
    return bestSeat;
}

struct DDKey { u64 h0,h1,h2,h3; int leader;
    bool operator==(const DDKey&o)const{return h0==o.h0&&h1==o.h1&&h2==o.h2&&h3==o.h3&&leader==o.leader;} };
struct DDKeyHash { size_t operator()(const DDKey&k)const{
    u64 x=1469598103934665603ull; for(u64 v:{k.h0,k.h1,k.h2,k.h3,(u64)k.leader}){x^=v;x*=1099511628211ull;} return (size_t)x; } };
struct DDBound { int8_t lo, hi; int8_t best = -1; };

// Relativ-rang-kanonisering: bare kortenes innbyrdes rekkefølge i hver farge
// betyr noe for dobbeltdummy-verdien, ikke absolutt valør. Vi komprimerer hver
// farges kort-i-spill til posisjoner 0..k-1 (pext), så mange absolutte
// stillinger deler samme TT-nøkkel. Fargeidentitet (trumf) bevares.
static inline DDKey canonKey(const SState& t){
    u64 c[4]={0,0,0,0};
    u64 uni=t.hands[0]|t.hands[1]|t.hands[2]|t.hands[3];
    for(int s=0;s<4;s++){
        u64 sm=suitMask(s);
        u64 u=(uni & sm) >> (s*13);
        for(int p=0;p<4;p++){
            u64 h=(t.hands[p] & sm) >> (s*13);
            c[p] |= _pext_u64(h,u) << (s*13);
        }
    }
    return DDKey{c[0],c[1],c[2],c[3],t.leader};
}

struct Dobbeltdummy {
    std::unordered_map<DDKey,DDBound,DDKeyHash> tt;
    Dobbeltdummy(){ tt.reserve(1<<14); }

    // MTD-f: konverger mot verdien via gjentatte null-vindu-søk. TT-en
    // (medlem) persisterer mellom iterasjonene og strammer grensene raskt.
    int solve(const SState& t){
        int maks = popcount(t.hands[t.leader]) + (t.trCount? 1:0);
        int g = maks/2, lower=-1, upper=maks+1;
        while(lower < upper){
            int beta = (g==lower)? g+1 : g;
            g = rec(t, beta-1, beta);
            if(g < beta) upper=g; else lower=g;
        }
        return g;
    }

    int rec(const SState& t,int alfa,int beta){
        u64 uni=t.hands[0]|t.hands[1]|t.hands[2]|t.hands[3];
        if(uni==0) return 0;
        bool atStart=(t.trCount==0);
        int maks=0; DDKey key; bool haveKey=false; int ttBest=-1;
        if(atStart){
            maks=popcount(t.hands[t.leader]);
            if(alfa>=maks) return maks;
            if(beta<=0) return 0;
            key=canonKey(t); haveKey=true;
            auto it=tt.find(key);
            if(it!=tt.end()){ DDBound g=it->second;
                if(g.lo>=beta) return g.lo;
                if(g.hi<=alfa) return g.hi;
                if(g.lo>alfa) alfa=g.lo;
                if(g.hi<beta) beta=g.hi;
                ttBest=g.best;
            }
        }
        int seat=t.active();
        bool erMaks = t.teamMask & (1<<seat);
        u64 unionMedStikk=uni; for(int i=0;i<t.trCount;i++) unionMedStikk|=bit(t.trCard[i]);
        int mv[13], n; reducedMoves(legalMask(t), unionMedStikk, mv, n);
        // Trekkordning: prøv TT-ens beste trekk først (trygt – hoppes over hvis
        // det ikke er lovlig i denne stillingen, f.eks. ved kanonisk deling).
        if(ttBest>=0) for(int i=0;i<n;i++) if(mv[i]==ttBest){ std::swap(mv[0],mv[i]); break; }

        int best = erMaks? -1 : 999, bestMove = mv[0];
        int a=alfa,b=beta, aOrig=alfa;
        for(int i=0;i<n;i++){
            SState c=t; int winner=applyMove(c,mv[i]); int val;
            if(winner>=0){ int bonus=(t.teamMask&(1<<winner))?1:0; val=bonus+rec(c,a-bonus,b-bonus); }
            else val=rec(c,a,b);
            if(erMaks){ if(val>best){best=val;bestMove=mv[i];} if(best>a)a=best; if(best>=b)break; }
            else      { if(val<best){best=val;bestMove=mv[i];} if(best<b)b=best; if(best<=a)break; }
        }
        if(haveKey){
            DDBound g; auto it=tt.find(key); g = it!=tt.end()? it->second : DDBound{0,(int8_t)maks,-1};
            if(best<=aOrig) g.hi=std::min<int>(g.hi,best);
            else if(best>=beta) g.lo=std::max<int>(g.lo,best);
            else { g.lo=(int8_t)best; g.hi=(int8_t)best; }
            g.best=(int8_t)bestMove;
            tt[key]=g;
        }
        return best;
    }
};

} // namespace wa
