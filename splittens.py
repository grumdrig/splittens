#!/usr/bin/python

"""Figure out my own dang statistics on how to play 21"""

i13 = 1.0/13.0  # 1/13 is about 7.7 %

hits = [min(10,r) for r in range(1,14)]
outcomes = range(17, 23)
upcards = range(2, 11) + [1]
paircards = upcards + []
paircards.reverse()

# Enumeration (of sorts) of the plays which can be made
STAY = ' -- '
HIT = 'HHHH'
DOUBLEDOWN = '2**2'
SPLIT = '<sp>'
BUST = 'bust'

dealer_hard_hand_outcome = {}
dealer_soft_hand_outcome = {}
# fill in the outcome arrays with zeroes
for h in range(2, 23):
  dealer_hard_hand_outcome[h] = {}
  dealer_soft_hand_outcome[h] = {}
  for o in outcomes:
    dealer_hard_hand_outcome[h][o] = 0.0
    dealer_soft_hand_outcome[h][o] = 0.0
for h in outcomes:
  dealer_hard_hand_outcome[h][h] = 1.0
  dealer_soft_hand_outcome[h-10][h] = 1.0
# then things get more complicated
for hand in range(16, 2-1, -1):
  for hit in hits:
    t = min(hand + hit, 22)
    if hit == 1 and t + 10 < 22:
      outs = dealer_soft_hand_outcome[t]
    else:
      outs = dealer_hard_hand_outcome[t]
    for outcome,p in outs.iteritems():
      dealer_hard_hand_outcome[hand][outcome] += p * 1.0/13.0
  if hand + 10 < 17:
    for hit in hits:
      t = hand + hit
      if t + 10 >= 22:
        outs = dealer_hard_hand_outcome[t]
      else:
        outs = dealer_soft_hand_outcome[t]
      for outcome,p in outs.iteritems():
        dealer_soft_hand_outcome[hand][outcome] += p * 1.0/13.0

dealer_showing_outcome = {}
for showing in upcards:
  dealer_showing_outcome[showing] = {}
  for o in outcomes + ['bj']:
    dealer_showing_outcome[showing][o] = 0.0
  for holecard in hits:
    if showing == 1:
      if holecard == 10:
        # This would have been a blackjack and your money's gone
        # already, so at decision-making time, we know the holecard
        # ain't a 10...
        holecardchance = 0.0
      else:
        # ...this all other cards will have a better chance of appearing.
        holdcardchance = 1.0/9.0
    else:
      # But normally, there's a 1/13 chance of each rank. Of course I
      # could speed the calculation up a trifle by lumping the 10s &
      # royals together
      holecardchance = 1.0/13.0
    total = showing + holecard
    if (showing == 10 and holecard == 1):
      # Hidden blackjack is worse than average case because it wins
      # would-be pushes
      dealer_showing_outcome[showing]['bj'] += holecardchance
    else:
      if (showing == 1 or holecard == 1) and total + 10 < 17:
        outs = dealer_soft_hand_outcome[total]
      else:
        outs = dealer_hard_hand_outcome[total]
      for o in outcomes:
        dealer_showing_outcome[showing][o] += outs[o] * 1.0/13.0

_r4stay = {}
def return_for_staying(dealer_showing, hand):
  if hand > 21: return 0.0
  cache_key = (dealer_showing, hand)
  if not _r4stay.has_key(cache_key):
    outs = dealer_showing_outcome[dealer_showing]
    expected_return = 0.0
    for dealer_total in outcomes:
      if dealer_total > 21 or dealer_total < hand:
        expected_return += 2 * outs[dealer_total]  # stake + winnings
      elif dealer_total == hand:
        expected_return += outs[dealer_total]  # push
      # Other cases (including bj) return 0
    _r4stay[cache_key] = expected_return
  return _r4stay[cache_key]

_r41hit = {}
def return_for_one_hit(showing, hand, soft):
  cache_key = (showing, hand, soft)
  if not _r41hit.has_key(cache_key):
    outs = dealer_showing_outcome[showing]
    returns = 0.0
    for hit in hits:
      player_total = hand + hit
      if player_total > 21 and soft:
        player_total -= 10
      if hit == 1 and player_total + 10 <= 21:
        player_total += 10
      returns += return_for_staying(showing, player_total) / 13.0
    _r41hit[cache_key] = returns
  return _r41hit[cache_key]

_r4dd = {}
def return_for_double_down(dealer_showing, hand, soft):
  key = (dealer_showing, hand, soft)
  if not _r4dd.has_key(key):
    _r4dd[key] = return_for_one_hit(dealer_showing, hand, soft) * 2.0 - 1.0
  return _r4dd[key]

_r4h = {}
def best_play(dealer_showing, hand, soft, first_two, pair):
  if hand >= 22 and soft:
    hand -= 10
    soft = False
  if hand >= 22:
    return BUST,0.0  # don't bother to cache busts
  if not first_two:
    pair = False

  # Peek in cache
  key = (dealer_showing, hand, soft, first_two, pair)
  if _r4h.has_key(key): return _r4h[key]

  if first_two and hand == 21:
    best_idea,best_return = STAY,2.5
  else:
    stay = return_for_staying(dealer_showing, hand)
    best_idea,best_return = STAY,stay
    if hand < 18:  # (We'll boldly assume you shouldn't hit 18+)
      play = 0.0
      for hit in hits:
        h2 = hand + hit
        s2 = soft
        if not soft and hit == 1 and h2 + 10 <= 22:
          s2 = True
          h2 += 10
        if s2 and h2 > 21:
          s2 = False
          h2 -= 10
        play += best_play(dealer_showing, h2, s2, False, False)[1] / 13.0
      if play > best_return:
        best_idea,best_return = HIT,play
    if first_two:
      ddown = return_for_double_down(dealer_showing, hand, soft)
      if ddown > best_return:
        best_idea,best_return = DOUBLEDOWN,ddown
    if first_two and pair:
      card = hand / 2
      if hand == 12: card = 1
      split = return_for_split(dealer_showing, card)
      if split > best_return:
        best_idea,best_return = SPLIT,split
  _r4h[key] = best_idea,best_return
  return best_idea,best_return


_r4split = {}
def return_for_split(dealer_showing, paircard):
  key = (dealer_showing, paircard)
  if not _r4split.has_key(key):
    for card in hits:
      expected_return = -1.0  # account for the extra bet
      # (but not positive about the math here)
      for hit in hits:
        hand = paircard + hit
        soft = paircard == 1 or hit == 1
        if soft: hand += 10
        dummy,value = best_play(dealer_showing,
                                hand,
                                soft,
                                True,
                                False) # NB:
        # To avoid problematic recursion, we claim this is not a pair.
        # Really, you're allowed to split up to 3 times in a hand, but
        # we'll just ignore that and leave it as a TODO.
        expected_return += 2.0 * value * 1.0/13.0
    _r4split[key] = expected_return
  return _r4split[key]


def main():
  print hits, outcomes
  print "Chance of each outcome given dealer's hand total"
  print "Hard   17  18  19  20  21 bust"
  for h in range(4,17):
    print "%4d:" % h,
    for t in outcomes:
      print "%3d" % (dealer_hard_hand_outcome[h][t] * 100),
    print '  ', sum(dealer_hard_hand_outcome[h].values()) * 100
  print "Soft   17  18  19  20  21 bust"
  for h in range(2,17-10):
    print "%4d:" % (h + 10),
    for t in outcomes:
      print "%3d" % (dealer_soft_hand_outcome[h][t] * 100),
    print '  ', sum(dealer_soft_hand_outcome[h].values()) * 100

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
      print "%4.2f" % return_for_staying(showing, hand),
    print

  print "Return expected for one hit"
  print "      Showing"
  print "Hard", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%4.2f" % return_for_one_hit(showing, hand, False),
    print
  print "Soft", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%4.2f" % return_for_one_hit(showing, hand, True),
    print

  print "Strategy delta, one hit - stay"
  print "      Showing"
  print "Hard", ("%5d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%5.2f" % (return_for_one_hit(showing, hand, False) -
                       return_for_staying(showing, hand)),
    print
  print "Soft", ("%5d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%5.2f" % (return_for_one_hit(showing, hand, True) -
                       return_for_staying(showing, hand)),
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
    hand = card * 2
    soft = card == 1
    if soft:
      hand += 10
    for showing in upcards:
      print "%5.2f" % (return_for_split(showing, card) -
                       max(return_for_one_hit(showing, hand, soft),
                           return_for_staying(showing, hand))),
    print

  print "Return expected for double down"
  print "      Showing"
  print "Hard", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(20, 4-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%5.2f" % return_for_double_down(showing, hand, soft=False),
    print
  print "Soft", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(21, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print "%5.2f" % return_for_double_down(showing, hand, soft=True),
    print

  print "Best play"
  print "      Showing"
  print "Hard", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(20, 4-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print best_play(showing, hand, False, True, False)[0],
    print
  print "Soft", ("%4d " * len(upcards)) % tuple(upcards)
  for hand in range(20, 12-1, -1):
    print "%4d" % hand,
    for showing in upcards:
      print best_play(showing, hand, True, True, False)[0],
    print
  print "Pair", ("%4d " * len(upcards)) % tuple(upcards)
  for card in paircards:
    print "%3ds" % card,
    for showing in upcards:
      hand = card * 2
      soft = card == 1
      if soft: hand += 10
      print best_play(showing, hand, soft, True, True)[0],
    print

  """
  print "COSTS PER BAD MOVE"
  price_out("split 10s when dealer shows 6",
            [(s,h
  
    you must split tens when dealer shows a 6 ($0.10)
  split tens when dealer shows 7 or less ($1.10)
  split everything but 5s and 10s
  split everything unless dealer shows 10,A
  """

  
# TODO: figure for multiple hits!!!!!

def card():
  """Deal a card. We're assuming deep multideck here."""
  return min(random.randrange(1, 13), 10)


if __name__ == "__main__":
  main()
  
