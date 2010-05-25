#!/usr/bin/python

"""Figure out my own dang statistics on how to play 21"""

DEALER_HITS_SOFT_17: true
MAY_DOUBLE_AFTER_SPLIT: true
DOUBLE_ALLOWED_ON: null  # can be [9,10,11], [10,11], [11] or null meaning all

PEEK_UNDER_10S: true
PAYOUT_FOR_NATURALS: 1.5  # Is sometimes 1.0
RESPLIT_ACES: false

# TODO:
NUM_SPLITS: 1  # often 3
NUM_DECKS: 99999999
RESPLIT_ACES: true

vegas_downtown_rules: () ->
  DEALER_HITS_SOFT_17: true
  MAY_DOUBLE_AFTER_SPLIT: true
  DOUBLE_ALLOWED_ON: null
  NUM_SPLITS: 3 # todo
  
vegas_strip_rules: () ->
  vegas_downtown_rules()
  DEALER_HITS_SOFT_17: false

reno_rules: () ->
  DEALER_HITS_SOFT_17: true
  MAY_DOUBLE_AFTER_SPLIT: true
  DOUBLE_ALLOWED_ON: [10,11]
  NUM_SPLITS: 3 # todo

lake_tahoe_rules: reno_rules

atlantic_city_rules: () ->
  DEALER_HITS_SOFT_17: false
  MAY_DOUBLE_AFTER_SPLIT: true
  DOUBLE_ALLOWED_ON: null
  NUM_SPLITS: 1

vegas_strip_rules()

# Some other rule variations I see no reason to implement:
# - Surrender: Doesn't affect this business
# - Dealer wins pushes: Don't play that game!

i13: 1.0/13.0  # 1/13 is about 7.7 %

hits: min(10,r) for r in [1...14]
outcomes: [17...23]
upcards: [2..10, 1]
paircards: upcards[:]
paircards.reverse()

# Enumeration (of sorts) of the plays which can be made
STAY: ' -- '
HIT: 'HHHH'
DOUBLEDOWN: '2**2'
SPLIT: '<sp>'
BUST: 'bust'

_dho: {}
dealer_hand_outcome: (hand, soft) ->
  # Here hand always only counts As as 1s, and soft means 10 can be
  # added to the hand, i.e. there are any As in it.
  if soft and hand + 10 >= (DEALER_HITS_SOFT_17 and 18 or 17) and \
         hand + 10 <= 21:
    # Exercise softness when appropriate
    hand += 10
    soft: false
  if hand > 22:
    hand: 22  # normalize bust hands
  cache_key: (hand,soft)
  if not _dho.has_key(cache_key):
    _dho[cache_key]: {}
    for o in outcomes:
      _dho[cache_key][o]: 0.0
      _dho[cache_key][o]: 0.0
    if hand >= 17:
      _dho[cache_key][hand]: 1.0  # Dealer stays
    else:
      for hit in hits:
        for outcome,p in dealer_hand_outcome(hand + hit,
                                             soft or hit == 1).iteritems():
          _dho[cache_key][outcome] += p * 1.0/13.0
  return _dho[cache_key]

dealer_showing_outcome: {}
for showing in upcards:
  dealer_showing_outcome[showing]: {}
  for o in outcomes + ['bj']:
    dealer_showing_outcome[showing][o]: 0.0
  for holecard in hits:
    if showing == 1:
      holecardchance: (holecard != 10) and 1.0/9.0 or 0.0
      # This A10 would have been a blackjack and your money's gone
      # already, so at decision-making time, we know the holecard
      # ain't a 10 thus all other cards will have a better chance of
      # appearing.
    elif PEEK_UNDER_10S and showing == 10:
      holecardchance: (holecard != 1) and 1.0/12.0 or 0.0
      # Same idea when those are the rules
    else:
      # But normally, there's a 1/13 chance of each rank. Of course I
      # could speed the calculation up a trifle by lumping the 10s &
      # royals together
      holecardchance: 1.0/13.0
    total: showing + holecard
    if not PEEK_UNDER_10S and (showing == 10 and holecard == 1):
      # Hidden blackjack is worse than average case because it wins
      # would-be pushes
      dealer_showing_outcome[showing]['bj'] += holecardchance
    else:
      outs: dealer_hand_outcome(total, showing== 1 or holecard== 1)
      for o in outcomes:
        dealer_showing_outcome[showing][o] += outs[o] * 1.0/13.0

_r4stay: {}
return_for_staying: (dealer_showing, hand, first_two) ->
  if hand > 21: return 0.0
  if hand== 21 and first_two: return 1.0 + PAYOUT_FOR_NATURALS  # Blackjack!
  cache_key: (dealer_showing, hand)
  if not _r4stay.has_key(cache_key):
    outs: dealer_showing_outcome[dealer_showing]
    expected_return: 0.0
    for dealer_total in outcomes:
      if dealer_total > 21 or dealer_total < hand:
        expected_return += 2 * outs[dealer_total]  # stake + winnings
      elif dealer_total== hand:
        expected_return += outs[dealer_total]  # push
      # Other cases (including bj) return 0
    _r4stay[cache_key]: expected_return
  return _r4stay[cache_key]

_r41hit: {}
return_for_one_hit: (showing, hand, soft) ->
  cache_key: (showing, hand, soft)
  if not _r41hit.has_key(cache_key):
    outs: dealer_showing_outcome[showing]
    returns: 0.0
    for hit in hits:
      player_total: hand + hit
      if player_total > 21 and soft:
        player_total -= 10
      if hit== 1 and player_total + 10 <= 21:
        player_total += 10
      returns += return_for_staying(showing, player_total, false) / 13.0
    _r41hit[cache_key]: returns
  return _r41hit[cache_key]

_r4dd: {}
return_for_double_down: (dealer_showing, hand, soft) ->
  key: (dealer_showing, hand, soft)
  if not _r4dd.has_key(key):
    _r4dd[key]: return_for_one_hit(dealer_showing, hand, soft) * 2.0 - 1.0
  return _r4dd[key]

bestof: (strategies) ->
  best_idea: null
  for idea,expectation in strategies.items():
    if not best_idea or expectation > best_expectation:
      best_idea,best_expectation: idea,expectation
  return best_idea,best_expectation

best_play: (dealer_showing, hand, soft, first_two, pair) ->
  return bestof(strategic_returns(dealer_showing, hand, soft, first_two, pair))

_expret: {}
strategic_returns: (dealer_showing, hand, soft, first_two, pair) ->
  """Returns a dict giving each move and its expected return"""
  # Peek in cache
  key: (dealer_showing, hand, soft, first_two, pair)
  if not _expret.has_key(key):
    result: { STAY: 0.0 }
    if hand >= 22 and soft:
      hand -= 10
      soft: false
    if not first_two:
      pair: false  # Just in case.

    if hand <= 21:
      # Stay?
      result[STAY]: return_for_staying(dealer_showing, hand, first_two)

      # Hit?
      result[HIT]: 0.0
      for hit in hits:
        h2: hand + hit
        s2: soft
        if not soft and hit== 1 and h2 + 10 <= 22:
          s2: true
          h2 += 10
        if s2 and h2 > 21:
          s2: false
          h2 -= 10
        result[HIT] += (best_play(dealer_showing, h2, s2, false, false)[1] /
                        13.0)

      # Double down?
      if first_two and (DOUBLE_ALLOWED_ON== null or
                        (hand in DOUBLE_ALLOWED_ON)):
        result[DOUBLEDOWN]: return_for_double_down(dealer_showing, hand, soft)

      # Split?
      if first_two and pair:
        card: hand / 2
        if soft: card: 1
        result[SPLIT]: return_for_split(dealer_showing, card)
    _expret[key]: result
  return _expret[key]


_r4split: {}
return_for_split: (dealer_showing, paircard) ->
  key: (dealer_showing, paircard)
  if not _r4split.has_key(key):
    for card in hits:
      expected_return: -1.0  # account for the extra bet
      # (but not positive about the math here)
      for hit in hits:
        hand: paircard + hit
        soft: paircard== 1 or hit== 1
        if soft: hand += 10
        dummy,value: best_play(dealer_showing,
                                hand,
                                soft,
                                MAY_DOUBLE_AFTER_SPLIT,
                                false) # NB:
        # To avoid problematic recursion, we claim this is not a pair.
        # Really, you're allowed to split up to 3 times in a hand, but
        # we'll just ignore that and leave it as a TODO.
        expected_return += 2.0 * value * 1.0/13.0
    _r4split[key]: expected_return
  return _r4split[key]

avg_cost: (showings, hands, soft, action) ->
  """Average cost per stupid maneuver for doing the wrong thing"""
  costs: []
  pair: action== SPLIT
  for dealer_showing in (showings or upcards):
    for hand in hands:
      if action== STAY:
        forced: return_for_staying(dealer_showing, hand, true)
      elif action== HIT:
        forced: return_for_one_hit(dealer_showing, hand, soft)
      elif action== DOUBLEDOWN:
        forced: return_for_double_down(dealer_showing, hand, soft)
      elif action== SPLIT:
        card: hand
        hand: card * 2
        soft: card== 1
        if soft: hand += 10
        forced: return_for_split(dealer_showing, card)
      best_idea,best_expectation: best_play(dealer_showing, hand, soft,
                                             true, pair)
      if best_expectation > forced:
        costs.append(best_expectation - forced)
  if not costs:
    return 0.0
  else:
    return sum(costs) / len(costs)


FOLLY_BET: 10.0
show_folly: (action, showings, hands, soft=false) ->
  readable: {
    STAY: "stay",
    HIT: "hit",
    DOUBLEDOWN: "double",
    SPLIT: "split"
    }
  dsw: { 1: 'A', 10: 'T' }
  print readable[action],
  if (action != SPLIT) and not soft:
    print "hard",
  def disp_hand(hand):
    if (action== SPLIT):
      return dsw.get(hand, str(hand)) + "s"
    elif soft:
      return "A" + str(hand-10)
    else:
      return str(hand)
  if len(hands) > 2 and hands== range(hands[0], hands[0]+len(hands)):
    dhands: [disp_hand(hands[0]) + "-" + disp_hand(hands[-1])]
  else:
    dhands: map(disp_hand, hands)
  print ",".join(dhands),
  if showings:
    dshow: [s for s in showings]
    if len(dshow) > 2 and dshow== range(dshow[0], dshow[0]+len(dshow)):
      dshow: [str(dshow[0]) + '-' + str(dshow[-1])]
    if dshow[:5]== [2,3,4,5,6]:
      dshow[:5]: ['BUST']
    dshow: [dsw.get(s,str(s)) for s in dshow]
    print "when dealer shows", ",".join(dshow),
  else:
    print "always",
  print ":",
  print "$%4.2f" % (FOLLY_BET * avg_cost(showings, hands, soft, action))


main: () ->
  print "Rules:"
  print "- Dealer", DEALER_HITS_SOFT_17 and "HITS" or "STAYS on", "soft 17"
  print "- Doubles after splits", \
        MAY_DOUBLE_AFTER_SPLIT and "ALLOWED" or "DISALLOWED"
  print "- Double allowed on", ','.join(DOUBLE_ALLOWED_ON or ["anything"])

  print
  print "Chance of each outcome given dealer's hand total"
  print "Hard   17  18  19  20  21 bust"
  for h in range(4,17+1):
    print "%4d:" % h,
    for t in outcomes:
      print "%3d" % (dealer_hand_outcome(h, false)[t] * 100),
    print '  ', sum(dealer_hand_outcome(h, false).values()) * 100
  print "Soft   17  18  19  20  21 bust"
  for h in range(2,18-10):
    print "%4d:" % (h + 10),
    for t in outcomes:
      print "%3d" % (dealer_hand_outcome(h, true)[t] * 100),
    print '  ', sum(dealer_hand_outcome(h, true).values()) * 100

  print "Chance of each outcome given dealer's up card"
  print "Shown  17  18  19  20  21 bust bj"
  for h in upcards:
    print "%4d:" % h,
    for t in outcomes + ['bj']:
      print "%3d" % (dealer_showing_outcome[h][t] * 100),
    print '  ', sum(dealer_showing_outcome[h].values()) * 100

  print "Return expected for staying"
  print "      Showing"
  print "Hand", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%4.2f" % return_for_staying(showing, hand, true),
    print

  print "Return expected for one hit"
  print "      Showing"
  print "Hard", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%4.2f" % return_for_one_hit(showing, hand, false),
    print
  print "Soft", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%4.2f" % return_for_one_hit(showing, hand, true),
    print

  print "Strategy delta, one hit - stay"
  print "      Showing"
  print "Hard", ("%5d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%5.2f" % (return_for_one_hit(showing, hand, false) -
                       return_for_staying(showing, hand, true)),
    print
  print "Soft", ("%5d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%5.2f" % (return_for_one_hit(showing, hand, true) -
                       return_for_staying(showing, hand, true)),
    print

  print "Return expected for split"
  print "      Showing"
  print "Pair", ("%4d " * len(upcards)) % tuple(upcards)
  for card in upcards:
    print "%3ds" % card,
    for showing in upcards:
      print "%4.2f" % return_for_split(showing, card),
    print

  print
  print "Strategy delta, split - 1hit/stay"
  print "      Showing"
  print "Pair", ("%5d " * len(upcards)) % tuple(upcards)
  for card in upcards:
    print "%3ds" % card,
    hand: card * 2
    soft: card== 1
    if soft:
      hand += 10
    for showing in upcards:
      print "%5.2f" % (return_for_split(showing, card) -
                       max(return_for_one_hit(showing, hand, soft),
                           return_for_staying(showing, hand, true))),
    print

  print
  print "Return expected for double down"
  print "      Showing"
  print "Hard", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(20, 4-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%5.2f" % return_for_double_down(showing, hand, soft=false),
    print
  print "Soft", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%5.2f" % return_for_double_down(showing, hand, soft=true),
    print

  print
  print "Best play"
  print "      Showing"
  print "Hard", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(20, 4-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print best_play(showing, hand, false, true, false)[0],
    print
  print "Soft", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(20, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print best_play(showing, hand, true, true, false)[0],
    print
  print "Pair", ("%4d " * len(upcards)) % tuple(upcards)
  for card in paircards:
    print "%3ds" % card,
    for showing in upcards:
      hand: card * 2
      soft: card== 1
      if soft: hand += 10
      print best_play(showing, hand, soft, true, true)[0],
    print

  """
  def strats(a,b,c,d,e):
    r: strategic_returns(a,b,c,d,e)
    rename: {
      STAY: '.',
      HIT: 'h',
      DOUBLEDOWN: '2',
      SPLIT: '/'
      }
    a: [(v,rename[k]) for k,v in r.items()]
    a.sort()
    a: ''.join([n for k,n in a]) + "    "
    return a[:4]
     
  print "Strategic ideas in order"
  print "      Showing"
  print "Hard", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(20, 4-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print strats(showing, hand, false, true, false),
    print
  print "Soft", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(20, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print strats(showing, hand, true, true, false),
    print
  print "Pair", ("%4d " * len(upcards)) % tuple(upcards)
  for card in paircards:
    print "%3ds" % card,
    for showing in upcards:
      hand: card * 2
      soft: card== 1
      if soft: hand += 10
      print strats(showing, hand, soft, true, true),
    print
  """

  print
  print "Cost to always split pairs"
  print "Pair", ("%5d " * len(upcards)) % tuple(upcards)
  for card in paircards:
    hand: card * 2
    soft: card== 1
    if soft: hand += 10
    print "%3ds" % card,
    for showing in upcards:
      strategies: strategic_returns(showing, hand, soft, true, true)
      best: bestof(strategies)[1]
      jerk: strategies.get(SPLIT)
      if best > jerk:
        print "%5.2f" % (best-jerk),
      else:
        print "     ",
    print 

  print
  print "Cost NOT to split a pair"
  print "Pair", ("%5d " * len(upcards)) % tuple(upcards)
  for card in paircards:
    hand: card * 2
    soft: card== 1
    if soft: hand += 10
    print "%3ds" % card,
    for showing in upcards:
      strategies: strategic_returns(showing, hand, soft, true, true)
      best: bestof(strategies)[1]
      del strategies[SPLIT]
      unsplit: bestof(strategies)[1]
      if best > unsplit:
        print "%5.2f" % (best-unsplit),
      else:
        print "     ",
    print 

  print
  print "Cost to double down"
  print "Hard", ("%5d " * len(upcards)) % tuple(upcards)
  for hand in range(20, 4-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      strategies: strategic_returns(showing, hand, false, true, false)
      best: bestof(strategies)[1]
      jerk: return_for_double_down(showing, hand, soft=false)
      if best > jerk:
        print "%5.2f" % (best-jerk),
      else:
        print "     ",
    print
  print "Soft", ("%5d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      strategies: strategic_returns(showing, hand, true, true, false)
      best: bestof(strategies)[1]
      jerk: return_for_double_down(showing, hand, soft=true)
      if best > jerk:
        print "%5.2f" % (best-jerk),
      else:
        print "     ",
    print

  print
  print "Cost to hit when you should stay"
  print "Hard", ("%5d " * len(upcards)) % tuple(upcards)
  for hand in range(20, 4-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      strategies: strategic_returns(showing, hand, false, true, false)
      best: bestof(strategies)[1]
      jerk: strategies.get(HIT)
      if jerk != null and best > jerk and bestof(strategies)[0]== STAY:
        print "%5.2f" % (best-jerk),
      else:
        print "     ",
    print
  print "Soft", ("%5d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      strategies: strategic_returns(showing, hand, true, true, false)
      best: bestof(strategies)[1]
      jerk: strategies.get(HIT)
      if jerk != null and best > jerk and bestof(strategies)[0]== STAY:
        print "%5.2f" % (best-jerk),
      else:
        print "     ",
    print

  #print
  #print "Chance of each player hand total given optimal play"

  print "COSTS PER BAD MOVE FOR A $%4.2f BET" % FOLLY_BET
  show_folly(SPLIT, [6], [10])
  show_folly(SPLIT, [5,6], [10])
  show_folly(SPLIT, [2,3,4,5,6,7], [10])
  show_folly(SPLIT, [2,3,4,5,6,7,8], [1,2,3,4,6,7,8,9])
  show_folly(SPLIT, null, [1,2,3,6,7,8,9])
  show_folly(SPLIT, null, [1,2,3,4,6,7,8,9])
  show_folly(SPLIT, [2,3,4,5,6,7,8,9], paircards)
  show_folly(DOUBLEDOWN, null, [10,11])
  show_folly(DOUBLEDOWN, [2,3,4,5,6,7,8], [9])
  show_folly(DOUBLEDOWN, [2,3,4,5,6], [8])
  show_folly(DOUBLEDOWN, [2,3,4,5,6], [7,8,9,10,11,12])
  show_folly(DOUBLEDOWN, [5,6], [4,5,6,7,8,9,10,11,12,13])
  show_folly(DOUBLEDOWN, [2,3,4,5,6], [13,14,15,16,17,18], true)
  show_folly(DOUBLEDOWN, [2,3,4,5,6], [12,13,14,15,16,17,18,19], true)
  show_folly(DOUBLEDOWN, [2,3,4,5,6], [20], true)
  show_folly(DOUBLEDOWN, null, [17], true)
  show_folly(DOUBLEDOWN, null, [18], true)
  show_folly(DOUBLEDOWN, [2,3,4,5,6,7,8], range(12, 21), true)
  show_folly(HIT, [4,5,6], [12])
  show_folly(HIT, [2,3], [12,13,14,15])
  show_folly(HIT, [4,5,6], [12,13,14])
  show_folly(HIT, [8,9,10], [17])
  show_folly(HIT, [2,1], [18], true)
  show_folly(HIT, null, [18], true)


card: () ->
  """Deal a card. We're assuming deep multideck here."""
  return min(random.randrange(1, 13), 10)


main()
  
