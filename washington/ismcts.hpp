// Washington – ISMCTS (Information Set Monte Carlo Tree Search) for kortspill.
// Fikser PIMCs strategy fusion: ett tre over informasjonsmengder, ny
// determinisering per iterasjon (Cowling, Powley & Whitehouse 2012).
// Gjenbruker Insight/sampleWorld/greedy/solver fra player.hpp.
#pragma once
#include "player.hpp"
#include <cmath>
namespace wa {

struct ISEdge { int move; int child; int n; double w; int avail; };
struct ISNode { int seat; std::vector<ISEdge> edges; };

struct ISMCTS {
    std::vector<ISNode> T;
    int exactFrom;
    double c = 0.7;              // UCB-utforskning
    int tricksTotal;
    int target;                 // kontraktkrav (bud, eller alle stikk)

    // Kontrakt-bevisst belønning i [0,1]: budlaget vil KLARE budet (binært),
    // med et lite stikk-tiebreak; forsvaret vil felle det.
    inline double perspektiv(int seat, uint8_t teamMask, int bidTeamTricks) const {
        bool klart = bidTeamTricks >= target;
        double r = (klart ? 1.0 : 0.0) + 0.02 * (double)bidTeamTricks / std::max(1,tricksTotal);
        r = std::min(1.0, r);
        return (teamMask & (1<<seat)) ? r : (1.0 - r);
    }

    int velg(const Round& R, int seat, int nIter, int exaktFra, std::mt19937_64& rng){
        exactFrom = exaktFra; tricksTotal = R.tricksTotal;
        target = (R.isSolo||R.isAmerikaner)? R.tricksTotal : R.highBid;
        Insight in = makeInsight(R, seat);
        u64 legal0 = R.legalPlay(seat);
        if((legal0&(legal0-1))==0) return lowest(legal0);
        T.clear(); T.push_back(ISNode{seat, {}});

        for(int it=0; it<nIter; it++){
            auto ow = sampleWorld(in, rng); if(!ow) continue; World w=*ow;
            SState s = buildState(in, w);
            int already=0; for(int p=0;p<4;p++) if(w.teamMask&(1<<p)) already+=R.tricksWon[p];

            std::vector<std::pair<int,int>> path; // (node, edgeIndex)
            int node=0; bool expanded=false;
            while(true){
                if((s.hands[0]|s.hands[1]|s.hands[2]|s.hands[3])==0) break;
                int seatNow = s.active();
                u64 lm = legalMask(s);
                u64 uni=s.hands[0]|s.hands[1]|s.hands[2]|s.hands[3];
                u64 unionAll=uni; for(int i=0;i<s.trCount;i++) unionAll|=bit(s.trCard[i]);
                int mv[13], nm; reducedMoves(lm, unionAll, mv, nm);

                // finn utprøvd/uprøvd blant lovlige-i-denne-verden
                int untried=-1;
                for(int i=0;i<nm;i++){ bool found=false; for(auto&e:T[node].edges) if(e.move==mv[i]){found=true;break;} if(!found){untried=mv[i];break;} }
                // oppdater availability for alle lovlige kanter
                for(int i=0;i<nm;i++) for(auto&e:T[node].edges) if(e.move==mv[i]){ e.avail++; break; }

                if(untried>=0){
                    T[node].edges.push_back(ISEdge{untried, -1, 0, 0.0, 1});
                    path.push_back({node,(int)T[node].edges.size()-1});
                    applyMove(s, untried);
                    T.push_back(ISNode{ s.active(), {} });
                    int childIdx=(int)T.size()-1;
                    T[node].edges.back().child=childIdx;
                    node=childIdx; expanded=true; break;
                }
                // UCB-valg blant lovlige kanter
                int bestE=-1; double bestU=-1e18;
                for(int i=0;i<(int)T[node].edges.size();i++){ auto&e=T[node].edges[i];
                    bool legalNow=false; for(int k=0;k<nm;k++) if(mv[k]==e.move){legalNow=true;break;}
                    if(!legalNow) continue;
                    double q = e.n>0? e.w/e.n : 0.5;
                    double u = q + c*std::sqrt(std::log((double)std::max(1,e.avail))/std::max(1,e.n));
                    if(u>bestU){bestU=u;bestE=i;}
                }
                if(bestE<0) break;
                path.push_back({node,bestE});
                applyMove(s, T[node].edges[bestE].move);
                node=T[node].edges[bestE].child;
            }

            // simulering (grådig + eksakt) → budgiverlagets stikk
            int future = rolloutTeamTricks(s, exactFrom);
            int bidTeam = already + future;

            // backprop: hver kant oppdateres fra setet-som-valgtes perspektiv
            for(auto& pr : path){
                ISNode& nd = T[pr.first]; ISEdge& e = nd.edges[pr.second];
                e.n++; e.w += perspektiv(nd.seat, w.teamMask, bidTeam);
            }
        }
        // rot: mest besøkte lovlige kant
        int best=-1, bestN=-1;
        for(auto&e:T[0].edges){ if((legal0&bit(e.move)) && e.n>bestN){bestN=e.n;best=e.move;} }
        if(best<0){ // fallback
            SState t{}; t.hands=R.hands; t.leader=R.trick.empty()?R.leader:R.trick.front().first; t.trump=R.trump;
            t.bidWinner=R.bidWinner; t.firstTrick=(R.trickNum==0); t.plikt=R.requestedPlayed?-1:R.askedCard;
            t.teamMask=(uint8_t)(1<<R.bidWinner); if(!R.isSolo&&R.partner>=0)t.teamMask|=(1<<R.partner);
            t.trCount=0; for(auto&p:R.trick){t.trSeat[t.trCount]=p.first;t.trCard[t.trCount]=p.second;t.trCount++;}
            return greedyPick(t);
        }
        return best;
    }
};

} // namespace wa
