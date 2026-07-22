// Washington – spillere: heuristikk-baseline, PIMC (determinisert MC + eksakt
// sluttspill) og PIMC med spillhistorikk-vekting (angrep A). Determinizer og
// grådig utrulling portert fra MesterVerden/MesterSolver.
#pragma once
#include "solver.hpp"
#include <optional>
#include <algorithm>
#include <cmath>
namespace wa {

static const u64 ALL52 = ((u64)1<<52)-1;
static inline std::vector<int> idxsVec(u64 m){ std::vector<int> v; while(m){v.push_back(lowest(m));m&=m-1;} return v; }

// ---- Heuristisk håndvurdering (bud/trumf) ----
static inline double estimerStikk(u64 hand, int trump){
    double est=0; int tc=popcount(hand&suitMask(trump));
    est += tc*0.55; if(tc>3) est += (tc-3)*0.4;
    for(int f=0;f<4;f++){ u64 fm=hand&suitMask(f); int inF=popcount(fm);
        u64 x=fm; while(x){ int idx=lowest(x); x&=x-1; int r=rankOf(idx);
            if(r==12) est += (f==trump?1.0:0.9);
            else if(r==11) est += inF>=2?0.65:0.3;
            else if(r==10) est += inF>=3?0.35:0.15;
        }
        if(f!=trump){ if(inF==0) est += std::min(2,tc)*0.45; else if(inF==1) est+=0.3; }
    }
    return est;
}
static inline std::pair<int,double> besteTrumf(u64 hand){
    int bs=0; double be=-1;
    for(int f=0;f<4;f++){ double e=estimerStikk(hand,f); if(e>be){be=e;bs=f;} }
    return {bs,be};
}

// ---- Grådig fullinformasjonspolicy (utrulling) – port av GrådigSpiller ----
static inline int gCost(int idx,int trump){ return (suitOf(idx)==trump?100:0)+rankOf(idx); }
static inline int gCheapest(u64 m,int trump){ int best=-1,bc=1e9; u64 x=m; while(x){int i=lowest(x);x&=x-1; int c=gCost(i,trump); if(c<bc){bc=c;best=i;}} return best; }
// Prinsipielt default-utspill: led lavt fra lengste sidefarge (etabler lengde)
// i stedet for det globalt billigste kortet.
static inline int leadFromLongest(u64 m,int trump){
    int bestSuit=-1,bestLen=0;
    for(int f=0;f<4;f++){ if(f==trump) continue; int len=popcount(m&suitMask(f)); if(len>bestLen){bestLen=len;bestSuit=f;} }
    if(bestSuit<0) return gCheapest(m,trump);
    return lowest(m&suitMask(bestSuit));
}
static bool gCanBeat(const SState&t,int seat,int best,int ledF){
    u64 hand=t.hands[seat], follow=hand&suitMask(ledF);
    if(follow){ if(suitOf(best)!=ledF) return false; return rankOf(highest(follow))>rankOf(best); }
    if(t.trump<0) return false; u64 tr=hand&suitMask(t.trump); if(!tr) return false;
    if(suitOf(best)==t.trump) return highest(tr)>best; return true;
}
static int greedyPick(const SState& t){
    u64 m=legalMask(t); if((m&(m-1))==0) return lowest(m);
    int seat=t.active();
    uint8_t myTeam = (t.teamMask&(1<<seat)) ? t.teamMask : (uint8_t)(~t.teamMask & 0xF);
    std::vector<int> foes; for(int s=0;s<4;s++) if(!(myTeam&(1<<s))) foes.push_back(s);
    u64 uni=t.hands[0]|t.hands[1]|t.hands[2]|t.hands[3];
    if(t.trCount==0){
        // utspill: budgiverlag trekker trumf mens fiender har trumf
        if(t.trump>=0 && (t.teamMask&(1<<seat))){
            u64 tm=suitMask(t.trump), foeTr=0; for(int f:foes) foeTr|=t.hands[f]; foeTr&=tm;
            u64 myTr=m&tm; if(foeTr&&myTr) return highest(myTr);
        }
        for(int f=0;f<4;f++){ if(f==t.trump) continue; u64 fm=suitMask(f), mine=m&fm; if(!mine) continue;
            int topp=highest(mine); if(topp!=highest(uni&fm)) continue;
            bool ok=true; for(int fo:foes){ if((t.hands[fo]&fm)==0 && t.trump>=0 && (t.hands[fo]&suitMask(t.trump))) { ok=false; break; } }
            if(ok) return topp;
        }
        return leadFromLongest(m,t.trump);   // prinsipielt default-utspill
    }
    int ledF=suitOf(t.trCard[0]); int bestSeat=t.trSeat[0], bestIdx=t.trCard[0];
    for(int i=1;i<t.trCount;i++) if(sbeats(t.trCard[i],bestIdx,t.trump)){bestSeat=t.trSeat[i];bestIdx=t.trCard[i];}
    std::vector<int> foesLeft, mateLeft;
    for(int k=t.trCount+1;k<4;k++){ int s=(t.leader+k)%4; if(std::find(foes.begin(),foes.end(),s)!=foes.end()) foesLeft.push_back(s); else if(s!=seat) mateLeft.push_back(s); }
    bool ourWin = (myTeam&(1<<bestSeat));
    auto anyBeat=[&](std::vector<int>&ss,int idx){ for(int s:ss) if(gCanBeat(t,s,idx,ledF)) return true; return false; };
    if(ourWin && !anyBeat(foesLeft,bestIdx)) return gCheapest(m,t.trump);
    std::vector<int> winners; { u64 x=m; while(x){int i=lowest(x);x&=x-1; if(sbeats(i,bestIdx,t.trump)) winners.push_back(i);} }
    std::sort(winners.begin(),winners.end(),[&](int a,int b){return gCost(a,t.trump)<gCost(b,t.trump);});
    for(int w:winners) if(!anyBeat(foesLeft,w)) return w;
    if(ourWin) return gCheapest(m,t.trump);
    if(anyBeat(mateLeft,bestIdx)) return gCheapest(m,t.trump);
    if(!winners.empty()) return winners.front();
    return gCheapest(m,t.trump);
}

// Grådig fram til exactFrom stikk igjen, eksakt derfra. Returnerer lagstikk.
static int rolloutTeamTricks(SState t, int exactFrom){
    int perSeat[4]={0,0,0,0};
    while((t.hands[0]|t.hands[1]|t.hands[2]|t.hands[3])!=0){
        int stikkIgjen = popcount(t.hands[t.leader]) + (t.trCount?1:0);
        if(stikkIgjen<=exactFrom) break;
        int idx=greedyPick(t); int w=applyMove(t,idx); if(w>=0) perSeat[w]++;
    }
    int team=0;
    if((t.hands[0]|t.hands[1]|t.hands[2]|t.hands[3])!=0){ Dobbeltdummy dd; team+=dd.solve(t); }
    for(int s=0;s<4;s++) if(t.teamMask&(1<<s)) team+=perSeat[s];
    return team;
}

// ---- Innsikt: hva et sete lovlig vet under spill ----
struct Insight {
    int seat, bidWinner, trump, tricksTotal, highBid;
    bool isSolo, isAmerikaner, iAmBidTeam;
    u64 myHand, unknown;
    std::array<int,4> cardsLeft;
    int deadUnknown;
    std::array<u64,4> forbidden;
    int askedIdx, pliktkort, knownPartner;
    std::vector<int> askCandidates;
    int leader; std::vector<std::pair<int,int>> current; bool firstTrick;
    int alreadyWonBid; // stikk budvinner alt har (uten makker – legges til per verden)
};

static Insight makeInsight(const Round& R, int seat){
    Insight in{}; in.seat=seat; in.bidWinner=R.bidWinner; in.trump=R.trump;
    in.tricksTotal=R.tricksTotal; in.highBid=R.highBid; in.isSolo=R.isSolo; in.isAmerikaner=R.isAmerikaner;
    in.myHand=R.hands[seat];
    for(int s=0;s<4;s++) in.cardsLeft[s]=popcount(R.hands[s]);
    in.unknown = ALL52 & ~in.myHand & ~R.played;
    if(seat==R.bidWinner){ in.unknown &= ~R.discard; in.deadUnknown=0; }
    else in.deadUnknown=4;
    in.forbidden={};
    // Renonser fra spill-loggen.
    { int i=0; int led=R.bidWinner; // leder for stikk 0
      std::vector<std::pair<int,int>> lg=R.playLog;
      int n=(int)lg.size();
      int pos=0;
      while(pos<n){
        int ledF=suitOf(lg[pos].second); int bestSeat=lg[pos].first,bestIdx=lg[pos].second;
        int cnt=std::min(4,n-pos);
        for(int k=0;k<cnt;k++){ int s=lg[pos+k].first,c=lg[pos+k].second;
            if(suitOf(c)!=ledF) in.forbidden[s]|=suitMask(ledF);
            if(pos==0 && s==R.bidWinner && R.trump>=0 && ledF!=R.trump) in.forbidden[R.bidWinner]|=suitMask(R.trump);
            if(k>0 && sbeats(c,bestIdx,R.trump)){bestSeat=s;bestIdx=c;}
        }
        if(cnt==4){ led=bestSeat; pos+=4; } else break;
      }
    }
    in.leader = R.trick.empty()? R.leader : R.trick.front().first;
    for(auto&p:R.trick) in.current.push_back({p.first,p.second});
    in.firstTrick = (R.trickNum==0);
    // Etterlyst kort / makker.
    bool askOut = (R.askedCard>=0 && !R.requestedPlayed);
    bool iHaveAsk = (R.askedCard>=0 && (in.myHand&bit(R.askedCard)));
    in.iAmBidTeam = (seat==R.bidWinner) || (R.partner==seat);
    in.knownPartner = R.isSolo? -1 : (R.requestedPlayed? R.partner : (iHaveAsk? seat : -1));
    in.pliktkort = (R.trickNum==0 && askOut)? R.askedCard : -1;
    if(R.askedCard>=0 && askOut && !iHaveAsk && (in.unknown&bit(R.askedCard))){
        in.askedIdx=R.askedCard;
        for(int s=0;s<4;s++) if(s!=seat && s!=R.bidWinner && (in.forbidden[s]&bit(R.askedCard))==0) in.askCandidates.push_back(s);
        if(in.askCandidates.empty()) for(int s=0;s<4;s++) if(s!=seat&&s!=R.bidWinner) in.askCandidates.push_back(s);
    } else in.askedIdx=-1;
    in.alreadyWonBid=0;
    return in;
}

struct World { std::array<u64,4> hands; int partner; uint8_t teamMask; };

template<class R>
static std::optional<World> sampleWorld(const Insight& in, R& rng){
    std::vector<int> pool = idxsVec(in.unknown);
    if(in.askedIdx>=0) pool.erase(std::remove(pool.begin(),pool.end(),in.askedIdx),pool.end());
    for(int attempt=0;attempt<120;attempt++){
        std::array<u64,4> hands{}; hands[in.seat]=in.myHand;
        int behov[5]; for(int s=0;s<4;s++) behov[s]=in.cardsLeft[s]; behov[in.seat]=0; behov[4]=in.deadUnknown;
        int partner=in.knownPartner;
        if(in.askedIdx>=0){
            std::vector<int> cand; for(int c:in.askCandidates) if(behov[c]>0) cand.push_back(c);
            if(cand.empty()) return std::nullopt;
            int v=cand[rng()%cand.size()]; hands[v]|=bit(in.askedIdx); if(!in.isSolo) partner=v; behov[v]--;
        }
        // mest bundne kort først
        std::shuffle(pool.begin(),pool.end(),rng);
        std::stable_sort(pool.begin(),pool.end(),[&](int a,int b){
            auto allow=[&](int x){int n=0;for(int s=0;s<5;s++) if(behov[s]>0&&(s==4||(in.forbidden[s]&bit(x))==0))n++;return n;};
            return allow(a)<allow(b); });
        bool ok=true;
        for(int c:pool){ int cand[5],nc=0,total=0;
            for(int s=0;s<5;s++) if(behov[s]>0 && (s==4||(in.forbidden[s]&bit(c))==0)){cand[nc++]=s;total+=behov[s];}
            if(nc==0){ok=false;break;}
            int r=rng()%total,pick=cand[0];
            for(int i=0;i<nc;i++){ r-=behov[cand[i]]; if(r<0){pick=cand[i];break;} }
            if(pick<4) hands[pick]|=bit(c); behov[pick]--;
        }
        if(!ok) continue;
        uint8_t lag=(uint8_t)(1<<in.bidWinner); if(!in.isSolo && partner>=0) lag|=(1<<partner);
        return World{hands, in.isSolo?-1:partner, lag};
    }
    return std::nullopt;
}

// Bygg søketilstand fra en verden + pågående stikk.
static SState buildState(const Insight& in, const World& w){
    SState t{}; t.hands=w.hands; t.leader=in.leader; t.trump=in.trump; t.teamMask=w.teamMask;
    t.bidWinner=in.bidWinner; t.firstTrick=in.firstTrick; t.plikt=in.pliktkort; t.trCount=0;
    for(auto&p:in.current){ t.trSeat[t.trCount]=p.first; t.trCard[t.trCount]=p.second; t.trCount++; }
    return t;
}

// Vekt for angrep A: hvor sannsynlig var de faktisk spilte kortene i verdenen.
// Enkel motstandsmodell: replay historikken; hvert ikke-eget trekk vurderes mot
// grådig-policyens rangering (softmaks). Verdener som forklarer spillet vektes opp.
static double worldWeight(const Insight& in, const World& w, const std::vector<std::pair<int,int>>& log){
    // Rekonstruer starttilstand: full hånd = nåværende + allerede spilte per sete.
    std::array<u64,4> full=w.hands;
    for(auto&p:log) full[p.first]|=bit(p.second);
    SState t{}; t.hands=full; t.leader=in.bidWinner; t.trump=in.trump; t.teamMask=w.teamMask;
    t.bidWinner=in.bidWinner; t.firstTrick=true; t.plikt=(in.pliktkort>=0?in.pliktkort:(in.askedIdx>=0?in.askedIdx:-1));
    t.trCount=0;
    double logw=0;
    for(auto&pl:log){
        int seat=t.active();
        u64 m=legalMask(t);
        int played=pl.second;
        if(seat!=in.seat && popcount(m)>1){
            // ranger lovlige kort etter grådig-ønske; sannsynlighet ~ softmaks(-rang)
            int mv[13],n; u64 uni=t.hands[0]|t.hands[1]|t.hands[2]|t.hands[3];
            u64 unionAll=uni; for(int i=0;i<t.trCount;i++) unionAll|=bit(t.trCard[i]);
            reducedMoves(m,unionAll,mv,n);
            int gp=greedyPick(t);
            // rang 0 til grådigvalget, ellers etter kostnadsnærhet
            double num=0, denom=0, chosen=0;
            for(int i=0;i<n;i++){ int c=mv[i];
                double s = (c==gp)?1.6 : 0.0;
                double e=std::exp(s); denom+=e; if(c==played||(suitOf(c)==suitOf(played)&&rankOf(c)==rankOf(played))) chosen=e; }
            if(chosen==0){ // played var sekvensredusert bort → bruk grådig-match
                chosen = (played==gp)? std::exp(1.6):std::exp(0.0);
                denom += chosen;
            }
            logw += std::log(std::max(1e-6, chosen/denom));
        }
        applyMove(t,played);
    }
    return std::exp(logw);
}

enum PlayPolicy { HEUR, PIMC_UNIFORM, PIMC_WEIGHTED };

// Kortvalg. HEUR = grådig; PIMC = determinisert MC + eksakt sluttspill.
template<class RNG>
static int choosePlay(const Round& R, int seat, PlayPolicy pol, int nWorlds, int exactFrom, RNG& rng){
    u64 legal = R.legalPlay(seat);
    if((legal&(legal-1))==0) return lowest(legal);
    if(pol==HEUR){
        SState t{}; t.hands=R.hands; t.leader=R.trick.empty()?R.leader:R.trick.front().first;
        t.trump=R.trump; t.bidWinner=R.bidWinner; t.firstTrick=(R.trickNum==0); t.plikt=R.requestedPlayed?-1:R.askedCard;
        t.teamMask=(uint8_t)(1<<R.bidWinner); if(!R.isSolo&&R.partner>=0)t.teamMask|=(1<<R.partner);
        t.trCount=0; for(auto&p:R.trick){t.trSeat[t.trCount]=p.first;t.trCard[t.trCount]=p.second;t.trCount++;}
        return greedyPick(t);
    }
    Insight in=makeInsight(R,seat);
    u64 unionAll = ALL52 & ~R.played;
    int cand[13],nc; reducedMoves(legal, unionAll, cand,nc);
    std::vector<double> score(nc,0.0); double wsum=0;
    int target = (R.isSolo||R.isAmerikaner)? R.tricksTotal : R.highBid;
    for(int wi=0; wi<nWorlds; wi++){
        auto ow=sampleWorld(in,rng); if(!ow) continue; World w=*ow;
        double weight = (pol==PIMC_WEIGHTED)? worldWeight(in,w,R.playLog) : 1.0;
        if(weight<=0) continue;
        int alreadyTeam=0; for(int s=0;s<4;s++) if(w.teamMask&(1<<s)) alreadyTeam+=R.tricksWon[s];
        SState base=buildState(in,w);
        for(int i=0;i<nc;i++){
            SState s=base; applyMove(s,cand[i]);
            int future=rolloutTeamTricks(s,exactFrom);
            int totalTeam=alreadyTeam+future;
            double val=(totalTeam>=target?1000.0:0.0)+totalTeam;
            score[i]+= weight * (in.iAmBidTeam? val : -val);
        }
        wsum+=weight;
    }
    if(wsum<=0) return greedyPick( [&]{ SState t{};t.hands=R.hands;t.leader=R.trick.empty()?R.leader:R.trick.front().first;t.trump=R.trump;t.bidWinner=R.bidWinner;t.firstTrick=(R.trickNum==0);t.plikt=R.requestedPlayed?-1:R.askedCard;t.teamMask=(uint8_t)(1<<R.bidWinner);if(!R.isSolo&&R.partner>=0)t.teamMask|=(1<<R.partner);t.trCount=0;for(auto&p:R.trick){t.trSeat[t.trCount]=p.first;t.trCard[t.trCount]=p.second;t.trCount++;}return t;}() );
    int best=0; for(int i=1;i<nc;i++) if(score[i]>score[best]) best=i;
    return cand[best];
}

// ---- Rene mask-helpere for vrak/trumf (brukt av simulert budgivning) ----
static u64 discardMask(u64 h16){
    auto bt=besteTrumf(h16); int trump=bt.first;
    std::vector<int> c=idxsVec(h16);
    std::sort(c.begin(),c.end(),[&](int a,int b){return gCost(a,trump)<gCost(b,trump);});
    u64 d=0; for(int k=0;k<4;k++) d|=bit(c[k]); return d;
}
static std::pair<int,int> trumpAskMask(u64 h12,u64 dead){
    auto bt=besteTrumf(h12); int suit=bt.first;
    u64 live=(~(h12|dead))&ALL52, lt=live&suitMask(suit);
    return {suit, lt?highest(lt):highest(live)};
}

// Simuler at 'declarer' spiller runden i en gitt (full) verden. Returnerer
// stikk per sete, makker og lagstikk. Grådig utrulling (rask, lik for alle).
struct Decl { std::array<int,4> perSeat; int partner; int teamTricks; };
static Decl simulateDeclare(std::array<u64,4> hands, u64 talong, int declarer, bool solo, int tricksTotal){
    u64 dh=hands[declarer]|talong; u64 disc=discardMask(dh); hands[declarer]=dh&~disc;
    auto ta=trumpAskMask(hands[declarer],disc); int suit=ta.first, ask=ta.second;
    int partner=-1; if(!solo) for(int s=0;s<4;s++) if(s!=declarer&&(hands[s]&bit(ask))){partner=s;break;}
    SState t{}; t.hands=hands; t.leader=declarer; t.trump=suit; t.bidWinner=declarer;
    t.teamMask=(uint8_t)(1<<declarer); if(partner>=0) t.teamMask|=(1<<partner);
    t.firstTrick=true; t.plikt=ask; t.trCount=0;
    std::array<int,4> perSeat{};
    while((t.hands[0]|t.hands[1]|t.hands[2]|t.hands[3])!=0){ int idx=greedyPick(t); int w=applyMove(t,idx); if(w>=0) perSeat[w]++; }
    int team=perSeat[declarer]+(partner>=0?perSeat[partner]:0);
    return {perSeat,partner,team};
}

// Simulert budgivning: sammenlign pass / hvert lovlig tallbud / Amerikaner /
// solo på forventet poengsum over samplede verdener. Boten byr som den vil.
template<class RNG>
static int chooseBidSim(const Round& R, int seat, int nWorlds, RNG& rng){
    auto legal=R.legalBids(seat); if(legal.empty()) return BID_PASS;
    if(legal.size()==1) return legal[0];
    u64 myHand=R.hands[seat];
    std::vector<int> pool=idxsVec(ALL52 & ~myHand);
    int T=R.tricksTotal;
    // EV-akkumulatorer
    std::array<double,15> ev{}; std::array<int,15> cnt{};
    bool canAmerik=false, canSolo=false, canPass=false;
    for(int b:legal){ if(b==BID_AMERIKANER)canAmerik=true; else if(b==BID_SOLO)canSolo=true; else if(b==BID_PASS)canPass=true; }
    for(int w=0; w<nWorlds; w++){
        std::shuffle(pool.begin(),pool.end(),rng);
        std::array<u64,4> hands{}; hands[seat]=myHand; u64 talong=0; int p=0;
        for(int off=1; off<=3; off++){ int s=(seat+off)%4; for(int k=0;k<12;k++) hands[s]|=bit(pool[p++]); }
        for(int k=0;k<4;k++) talong|=bit(pool[p++]);
        // Min deklarasjon med makker (dekker tallbud + Amerikaner)
        Decl a=simulateDeclare(hands,talong,seat,false,T);
        for(int b:legal){ if(b>=R.minBid&&b<=R.maxBid){ bool made=a.teamTricks>=b; ev[b]+= made?2*b:-2*b; cnt[b]++; } }
        if(canAmerik){ bool made=a.teamTricks==T; ev[BID_AMERIKANER]+= made? R.targetScore/2 : -R.targetScore/2; cnt[BID_AMERIKANER]++; }
        // Min solo-deklarasjon
        if(canSolo){ Decl s=simulateDeclare(hands,talong,seat,true,T); bool made=s.perSeat[seat]==T; ev[BID_SOLO]+= made?R.targetScore:-R.targetScore; cnt[BID_SOLO]++; }
        // Pass: nåværende høybyder (ellers sterkeste motstander) deklarerer
        if(canPass){
            int d=-1, lvl=R.highBid;
            if(R.highSeat>=0 && R.highSeat!=seat && R.highBid>=R.minBid){ d=R.highSeat; }
            else { double best=-1; for(int o=0;o<4;o++) if(o!=seat){ double e=besteTrumf(hands[o]).second+2; if(e>best){best=e; d=o; lvl=std::max(R.minBid,std::min(R.maxBid,(int)std::lround(e)));} } if(best< R.minBid) d=-1; }
            double mine=0;
            if(d>=0){ Decl c=simulateDeclare(hands,talong,d,false,T); bool made=c.teamTricks>=lvl;
                if(c.partner==seat) mine = made? lvl : -lvl; else mine = c.perSeat[seat]; }
            ev[BID_PASS]+=mine; cnt[BID_PASS]++;
        }
    }
    int best=-1; double bestEv=-1e18;
    for(int b:legal){ if(cnt[b]==0) continue; double e=ev[b]/cnt[b]; if(e>bestEv){bestEv=e;best=b;} }
    return best<0? BID_PASS : best;
}

// ---- Delte heuristiske bud/vrak/trumf-policyer (like for alle spillere) ----
static int chooseBid(const Round& R, int seat){
    auto lb=R.legalBids(seat); if(lb.empty()) return BID_PASS;
    auto bt=besteTrumf(R.hands[seat]); double est=bt.second+2.0;
    int want=(int)std::lround(est);
    int bestNum=-1; for(int b:lb) if(b>=R.minBid&&b<=R.maxBid){ if(bestNum<0||b<bestNum) bestNum=b; }
    if(bestNum>=0 && bestNum<=want) return bestNum;
    return BID_PASS;
}
static u64 chooseDiscard(const Round& R){
    u64 h=R.hands[R.bidWinner]; auto bt=besteTrumf(h); int trump=bt.first;
    std::vector<int> cards=idxsVec(h);
    std::sort(cards.begin(),cards.end(),[&](int a,int b){ return gCost(a,trump)<gCost(b,trump); });
    u64 d=0; for(int k=0;k<4;k++) d|=bit(cards[k]); return d;
}
static std::pair<int,int> chooseTrumpAsk(const Round& R){
    u64 h=R.hands[R.bidWinner]; auto bt=besteTrumf(h); int suit=bt.first;
    u64 forbidden=h|R.discard; u64 live=(~forbidden)&ALL52;
    u64 lt=live&suitMask(suit); int ask = lt? highest(lt) : highest(live);
    return {suit,ask};
}

} // namespace wa
