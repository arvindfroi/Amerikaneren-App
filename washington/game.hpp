// Prosjekt Washington – C++-spillmotor for Amerikaneren (main-reglene).
// Byttekort standard (12 kort/hånd + 4 i talong), alltid trumf, Amerikaner
// (alle stikk m/makker) og solo-amerikaner (alle stikk alene, m/trumf),
// 2×/1×-poeng, mål 100. Kortindeks 0..51 = farge*13 + (valør-2).
#pragma once
#include <cstdint>
#include <array>
#include <vector>
#include <random>
#include <cassert>
#include <functional>

namespace wa {

using u64 = uint64_t;
static inline int suitOf(int c){ return c/13; }
static inline int rankOf(int c){ return c%13; }          // 0=2 ... 12=Ess
static inline u64 bit(int c){ return u64(1)<<c; }
static inline u64 suitMask(int s){ return u64(0x1FFF) << (s*13); }
static inline int popcount(u64 x){ return __builtin_popcountll(x); }
static inline int lowest(u64 m){ return __builtin_ctzll(m); }
static inline int highest(u64 m){ return 63 - __builtin_clzll(m); }

// Budkoder: 0=pass, 5..12=tallbud, 13=Amerikaner, 14=solo-amerikaner.
enum { BID_PASS=0, BID_AMERIKANER=13, BID_SOLO=14 };
static inline int bidRang(int b){ return b==BID_PASS ? -1 : b; } // pass lavest

enum Phase { P_BID, P_DISCARD, P_TRUMP, P_PLAY, P_DONE, P_REDEAL };

struct Round {
    // Oppsett
    int players = 4;
    int tricksTotal = 12;      // byttekort → 12 stikk
    int minBid = 5, maxBid = 12;
    int targetScore = 100;
    int dealer = 0;

    // Tilstand
    Phase phase = P_BID;
    std::array<u64,4> hands{};
    u64 talong = 0;            // 4 kort til overs
    u64 discard = 0;           // budvinnerens 4 vrakede kort
    std::array<int,4> tricksWon{};
    std::array<int,4> scoreDelta{};

    // Budrunde
    std::vector<std::pair<int,int>> bids; // (seat, code)
    u64 passed = 0;
    int highBid = BID_PASS, highSeat = -1;
    int activeBidder = 0;

    // Kontrakt
    int bidWinner = -1, trump = -1, askedCard = -1, partner = -1;
    bool isAmerikaner=false, isSolo=false;

    // Stikkspill
    std::vector<std::pair<int,int>> trick; // (seat, card)
    int leader = 0;
    int trickNum = 0;
    u64 played = 0;
    bool requestedPlayed = false;
    std::vector<std::pair<int,int>> playLog; // (seat,card) i spillrekkefølge

    std::mt19937_64 rng;

    explicit Round(u64 seed){ rng.seed(seed); }

    // ---- Utdeling ----
    void deal(){
        std::array<int,52> d; for(int i=0;i<52;i++) d[i]=i;
        for(int i=51;i>0;i--){ std::uniform_int_distribution<int> u(0,i); std::swap(d[i], d[u(rng)]); }
        for(auto&h:hands) h=0; talong=0;
        int idx=0;
        for(int s=0;s<4;s++) for(int k=0;k<12;k++) hands[s]|=bit(d[idx++]);
        for(int k=0;k<4;k++) talong|=bit(d[idx++]);
        phase=P_BID; activeBidder=(dealer+1)%4; passed=0; highBid=BID_PASS; highSeat=-1; bids.clear();
        tricksWon={}; scoreDelta={}; discard=0; trick.clear(); trickNum=0; played=0; playLog.clear();
        bidWinner=trump=askedCard=partner=-1; isAmerikaner=isSolo=false; requestedPlayed=false; leader=0;
    }

    // ---- Budrunde ----
    std::vector<int> legalBids(int seat) const {
        std::vector<int> out;
        if(phase!=P_BID || seat!=activeBidder || (passed&bit(seat))) return out;
        out.push_back(BID_PASS);
        int floor = std::max(minBid, bidRang(highBid)+1);
        for(int n=floor;n<=maxBid;n++) out.push_back(n);
        if(bidRang(highBid) < BID_AMERIKANER) out.push_back(BID_AMERIKANER);
        if(bidRang(highBid) < BID_SOLO) out.push_back(BID_SOLO); // solo slår alt
        return out;
    }

    // Returnerer true når budrunden er ferdig (kontrakt satt) eller redeal.
    void applyBid(int seat, int code){
        bids.push_back({seat,code});
        if(code==BID_PASS){ passed|=bit(seat); }
        else { highBid=code; highSeat=seat; }

        // Solo avslutter umiddelbart.
        if(code==BID_SOLO){ finishBidding(seat); return; }

        int active = 0, last=-1;
        for(int s=0;s<4;s++) if(!(passed&bit(s))){ active++; last=s; }
        if(active==0){ phase=P_REDEAL; return; }
        if(active==1 && highSeat!=-1){ finishBidding(highSeat); return; }
        int nxt=(activeBidder+1)%4; while(passed&bit(nxt)) nxt=(nxt+1)%4; activeBidder=nxt;
    }

    void finishBidding(int winner){
        bidWinner=winner; highSeat=winner;
        isSolo = (highBid==BID_SOLO);
        isAmerikaner = (highBid==BID_AMERIKANER);
        // Budvinner tar opp talongen for vraking.
        hands[winner]|=talong;
        phase=P_DISCARD;
    }

    // ---- Vraking (byttekort) ----
    // 'toDiscard' er 4 kort fra budvinnerens 16.
    void applyDiscard(u64 toDiscard){
        assert(popcount(toDiscard)==4);
        assert((toDiscard & ~hands[bidWinner])==0);
        hands[bidWinner]&=~toDiscard; discard=toDiscard; phase=P_TRUMP;
    }

    // ---- Trumf + etterlyst kort ----
    // askIdx = -1 tillatt kun ved solo (ingen makker).
    void applyTrump(int suit, int askIdx){
        trump=suit;
        askedCard=askIdx;
        partner=-1; requestedPlayed=(askIdx<0);
        if(askIdx>=0){
            assert((bit(askIdx)&hands[bidWinner])==0 && (bit(askIdx)&discard)==0);
            for(int s=0;s<4;s++) if(hands[s]&bit(askIdx)){ if(!isSolo) partner=s; break; }
        }
        phase=P_PLAY; leader=bidWinner; trick.clear(); trickNum=0; requestedPlayed=(askIdx<0);
    }

    // ---- Stikkspill ----
    int active() const { return (leader + (int)trick.size())%4; }

    u64 legalPlay(int seat) const {
        if(phase!=P_PLAY || seat!=active()) return 0;
        u64 hand=hands[seat], m=hand;
        if(!trick.empty()){
            int led = suitOf(trick.front().second);
            u64 follow = hand & suitMask(led);
            if(follow) m=follow;
        } else if(trickNum==0 && seat==bidWinner && trump>=0){
            u64 tr = hand & suitMask(trump);       // utspillsplikt: åpne i trumf
            if(tr) m=tr;
        }
        // Makkerplikt: etterlyst kort må legges i første stikk hvis lovlig.
        if(trickNum==0 && !requestedPlayed && askedCard>=0 && seat!=bidWinner
           && (m&bit(askedCard))) return bit(askedCard);
        return m;
    }

    static bool beats(int c, int best, int trump){
        int sc=suitOf(c), sb=suitOf(best);
        if(sc==sb) return rankOf(c)>rankOf(best);
        return sc==trump;
    }

    void applyPlay(int seat, int card){
        assert(legalPlay(seat)&bit(card));
        hands[seat]&=~bit(card); trick.push_back({seat,card}); played|=bit(card);
        playLog.push_back({seat,card});
        if(card==askedCard) requestedPlayed=true;
        if((int)trick.size()==4){
            int bestSeat=trick[0].first, bestCard=trick[0].second;
            for(size_t i=1;i<trick.size();i++) if(beats(trick[i].second,bestCard,trump)){ bestSeat=trick[i].first; bestCard=trick[i].second; }
            tricksWon[bestSeat]++; leader=bestSeat; trick.clear(); trickNum++;
            if(trickNum==tricksTotal) score();
        }
    }

    // ---- Poeng ----
    void score(){
        scoreDelta={};
        int M=targetScore;
        auto others=[&](int except1,int except2){ for(int s=0;s<4;s++) if(s!=except1&&s!=except2) scoreDelta[s]+=tricksWon[s]; };
        if(isSolo){
            bool made = tricksWon[bidWinner]==tricksTotal;
            scoreDelta[bidWinner]+= made? M : -M;
            others(bidWinner,-1);
        } else if(isAmerikaner){
            int teamT=tricksWon[bidWinner]+(partner>=0?tricksWon[partner]:0);
            bool made = teamT==tricksTotal;
            scoreDelta[bidWinner]+= made? M/2 : -M/2;
            if(partner>=0) scoreDelta[partner]+= made? M/4 : -M/4;
            others(bidWinner,partner);
        } else {
            int n=highBid;
            int teamT=tricksWon[bidWinner]+(partner>=0?tricksWon[partner]:0);
            bool made = teamT>=n;
            scoreDelta[bidWinner]+= made? 2*n : -2*n;
            if(partner>=0) scoreDelta[partner]+= made? n : -n;
            others(bidWinner,partner);
        }
        phase=P_DONE;
    }
};

} // namespace wa
