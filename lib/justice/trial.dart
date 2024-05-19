/* monthly - hold trial on a liberal */
import 'dart:math';

import 'package:lcs_new_age/common_actions/common_actions.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/items/armor.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/justice/prison.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

enum TrialOutcome {
  retrial,
  acquittal,
  guilty,
  lenience,
}

Future<void> trial(Creature g) async {
  TrialOutcome trialOutcome;

  // If their old base is no longer under LCS control, wander back to the
  // homeless camp instead.
  if (g.base?.controller != SiteController.lcs) {
    g.base = findSiteInSameCity(g.base?.city, SiteType.homelessEncampment);
  }
  g.location = g.base;

  erase();
  mvaddstrc(1, 1, white, g.name);
  addstr(" is standing trial.");
  await getKey();

  setColor(lightGray);

  if (!g.isCriminal) criminalize(g, Crime.loitering);

  int typenum = 0, scarefactor = 0;
  // *JDS* Scarefactor is the severity of the case against you; if you're a really
  // nasty person with a wide variety of major charges against you, then scarefactor
  // can get up there

  for (var c in g.wantedForCrimes.entries.where((e) => e.value > 0)) {
    typenum++;
    scarefactor += crimeHeat(c.key) * c.value;
  }

  //CHECK FOR SLEEPERS
  Creature? sleeperjudge;
  Creature? sleeperlawyer;
  int maxsleeperskill = 0;
  for (Creature p in pool.where((p) =>
      p.alive && p.sleeperAgent && p.location?.city == g.location?.city)) {
    if (p.type.id == CreatureTypeIds.conservativeJudge ||
        p.type.id == CreatureTypeIds.liberalJudge) {
      if (p.infiltration * 100 >= lcsRandom(100)) sleeperjudge = p;
    }
    if (p.type.id == CreatureTypeIds.lawyer) {
      if (p.skill(Skill.law) + p.skill(Skill.persuasion) >= maxsleeperskill) {
        sleeperlawyer = p;
        maxsleeperskill = p.skill(Skill.law) + p.skill(Skill.persuasion);
      }
    }
  }

  //STATE CHARGES
  setColor(lightGray);
  move(3, 1);
  if (sleeperjudge != null) {
    addstr(
        "Sleeper ${sleeperjudge.name} reads the charges, trying to hide a smile:");
    g.confessions = 0; // Sleeper judge prevents these lunatics from testifying
  } else {
    addstr("The judge reads the charges:");
  }

  mvaddstrc(5, 1, red, "The defendant, ${g.properName}, is charged with ");
  int x = 2, y = 5;
  Future<void> listCrime(Crime crime) async {
    typenum--;
    if ((x++) >= 2) {
      x = 0;
      move(++y, 1);
    }
    if (g.wantedForCrimes[crime]! > 0) {
      if ((x++) >= 2) {
        x = 0;
        move(++y, 1);
      }
      if (g.wantedForCrimes[crime]! > 1) {
        addstr("${g.wantedForCrimes[crime]!} counts of ");
      }
      addstr(crime.chargedWith);
    }
    if (typenum > 1) addstr(", ");
    if (typenum == 1) addstr(" and ");
    if (typenum == 0) addstr(".");
    await getKey();
  }

  for (var c in g.wantedForCrimes.entries.where((e) => e.value > 0)) {
    await listCrime(c.key);
  }

  if (g.confessions > 0) {
    move(y += 2, 1);
    if (g.confessions > 1) {
      addstr(
          "${g.confessions} former LCS members will testify against ${g.name}");
    } else {
      addstr("A former LCS member will testify against ${g.name}.");
    }

    await getKey();
  }

  //CHOOSE DEFENSE
  mvaddstrc(y + 2, 1, lightGray, "How will you conduct the defense?");

  y += 4;
  mvaddstr(y++, 1, "A - Use a court-appointed attorney.");
  mvaddstr(y++, 1, "B - Defend self!");
  mvaddstr(y++, 1, "C - Plead guilty.");
  mvaddstrc(y++, 1, ledger.funds < 5000 ? darkGray : lightGray,
      "D - Pay \$5000 to hire Elite Liberal Attorney ${uniqueCreatures.aceLiberalAttorney.name}.");
  if (sleeperlawyer != null) {
    mvaddstrc(y++, 1, lightGray,
        "E - Accept sleeper ${sleeperlawyer.name}'s offer to assist pro bono.");
  }
  mvaddstrc(++y, 5, lightGray, "Your attributes if you defend yourself: ");
  mvaddstr(++y, 5, "Heart: ${g.attribute(Attribute.heart)}");
  mvaddstr(y, 25, "Persuasion: ${g.skill(Skill.persuasion)}");
  mvaddstr(++y, 5, "Charisma: ${g.attribute(Attribute.charisma)}");
  mvaddstr(y++, 25, "Law: ${g.skill(Skill.law)}");
  mvaddstr(y++, 5, "Intelligence: ${g.attribute(Attribute.intelligence)}");

  int defense;
  int c;
  String? attorneyname;
  while (true) {
    c = await getKey();
    if (c == Key.a) {
      defense = 0;
      break;
    }
    if (c == Key.b) {
      defense = 1;
      break;
    }
    if (c == Key.c) {
      defense = 2;
      break;
    }
    if (c == Key.d && ledger.funds >= 5000) {
      ledger.subtractFunds(5000, Expense.legalFees);
      defense = 3;
      attorneyname = uniqueCreatures.aceLiberalAttorney.name;
      break;
    }
    if (c == Key.e && sleeperlawyer != null) {
      defense = 4;
      attorneyname = sleeperlawyer.name;
      break;
    }
  }

  //TRIAL
  if (defense != 2) {
    int prosecution = 0;
    erase();

    mvaddstrc(1, 1, white, g.name);
    addstr(" is standing trial.");

    //TRIAL MESSAGE
    mvaddstrc(3, 1, lightGray, "The trial proceeds.  Jury selection is first.");

    await getKey();

    //JURY MAKEUP MESSAGE
    setColor(lightGray);
    move(5, 1);
    int jury = lcsRandom(61) -
        (60 * politics.publicMood()) ~/
            100; // Political leanings of the population determine your jury
    if (sleeperjudge != null) jury -= 20;
    if (defense == 3) // Hired $5000 ace attorney
    {
      if (!oneIn(10)) {
        addstr(
            "$attorneyname ensures the jury is stacked in ${g.name}'s favor!");

        if (jury > 0) jury = 0;
        jury -= 30;
      } else {
        setColor(red);
        addstr(
            "$attorneyname's CONSERVATIVE ARCH-NEMESIS will represent the prosecution!!!");

        jury = 0;
        prosecution += 100; // DUN DUN DUN!!
      }
    } else if (jury <= -29) {
      setColor(lightGreen);
      switch (lcsRandom(4)) {
        case 0:
          addstr("${g.name}'s best friend from childhood on the jury.");
        case 1:
          addstr("The jury is Flaming Liberal.");
        case 2:
          addstr("A few of the jurors are closet Socialists.");
        case 3:
          addstr(
              "One of the jurors flashes a SECRET LIBERAL HAND SIGNAL when no one is looking.");
      }
    } else if (jury <= -15) {
      addstr("The jury is fairly Liberal.");
    } else if (jury < 15) {
      addstr("The jury is quite moderate.");
    } else if (jury < 29) {
      addstr("The jury is a bit Conservative.");
    } else {
      setColor(yellow);
      switch (lcsRandom(4)) {
        case 0:
          addstr(
              "Such a collection of Conservative jurors has never before been assembled.");
        case 1:
          addstr("One of the accepted jurors is a Conservative activist.");
        case 2:
          addstr("A few of the jurors are members of the KKK.");
        case 3:
          addstr("The jury is frighteningly Conservative.");
      }
    }

    await getKey();

    //PROSECUTION MESSAGE
    // *JDS* The bigger your record, the stronger the evidence
    prosecution += 40 + lcsRandom(101) + scarefactor + (20 * g.confessions);
    if (sleeperjudge != null) prosecution >>= 1;
    if (defense == 3) prosecution -= 60;

    setColor(lightGray);
    move(7, 1);

    if (prosecution <= 50) {
      addstr("The prosecution's presentation is terrible.");
    } else if (prosecution <= 75) {
      addstr("The prosecution gives a standard presentation.");
    } else if (prosecution <= 125) {
      addstr("The prosecution's case is solid.");
    } else if (prosecution <= 175) {
      addstr("The prosecution makes an airtight case.");
    } else {
      addstr("The volume of evidence is overwhelming and incredibly damning.");
    }

    await getKey();

    jury += lcsRandom(prosecution ~/ 2 + 1) + prosecution ~/ 2;

    //DEFENSE MESSAGE
    setColor(lightGray);
    move(9, 1);

    int defensepower = 0;
    if (defense == 0 || defense == 3 || defense == 4) {
      if (defense == 0) {
        defensepower = lcsRandom(71); // Court-appointed attorney
      } else if (defense == 3) {
        defensepower = lcsRandom(71) + 80; // Ace Liberal attorney
      } else if (defense == 4) {
        // Sleeper attorney
        defensepower = lcsRandom(71) +
            sleeperlawyer!.skill(Skill.law) * 2 +
            sleeperlawyer.skill(Skill.persuasion) * 2;
        sleeperlawyer.train(Skill.law, prosecution);
        sleeperlawyer.train(Skill.persuasion, prosecution);
      }

      if (defensepower <= 5) {
        addstr("The defense attorney rarely showed up.");
      } else if (defensepower <= 15) {
        addstr(
            "The defense attorney accidentally said \"My client is GUILTY!\" during closing.");
      } else if (defensepower <= 25) {
        addstr("The defense is totally lame.");
      } else if (defensepower <= 50) {
        addstr("The defense was lackluster.");
      } else if (defensepower <= 75) {
        addstr("Defense arguments were pretty good.");
      } else if (defensepower <= 100) {
        addstr("The defense was really slick.");
      } else if (defensepower <= 145) {
        if (prosecution < 100) {
          addstr("The defense makes the prosecution look like amateurs.");
        } else {
          addstr("The defense is extremely compelling.");
        }
      } else {
        if (prosecution < 100) {
          addstr(
              "$attorneyname's arguments made several of the jurors stand up ");
          mvaddstr(10, 1,
              "and shout \"NOT GUILTY!\" before deliberations even began.");
          if (defense == 4) addjuice(sleeperlawyer!, 10, 500); // Bow please
        } else {
          addstr(attorneyname!);
          addstr(" conducts an incredible defense.");
        }
      }
    }
    if (defense == 1) {
      // *JDS* LEGAL SELF-REPRESENTATION: To succeed here, you really need to have two skills be
      // high: persuasion and law, with law being 1.5 times as influential. You can't have
      // just one or just the other. Even if you're a very persuasive person, the court will eat
      // you alive if you can't sound intelligent when talking about the relevant charges, and you
      // won't be able to fool the jury into letting you go if you aren't persuasive, as no
      // matter how encyclopedic your legal knowledge is, it's all in the pitch.
      //
      // If either your persuasion or your law roll is too low, you'll end up getting a negative
      // result that will drag down your defense. So try not to suck in either area.
      defensepower = 5 * (g.skillRoll(Skill.persuasion) - 5) +
          10 * (g.skillRoll(Skill.law) - 5);
      g.train(Skill.persuasion, 50);
      g.train(Skill.law, 50);

      addstr(g.name);
      if (defensepower <= 0) {
        addstr(" just made ${g.gender.himselfHerself} look guilty.");
      } else if (defensepower <= 25) {
        addstr("'s case really sucked.");
      } else if (defensepower <= 50) {
        addstr(" did all right, but made some mistakes.");
      } else if (defensepower <= 75) {
        addstr("'s arguments were pretty good.");
      } else if (defensepower <= 100) {
        addstr(" worked the jury very well.");
      } else if (defensepower <= 150) {
        addstr(" made a very powerful case.");
      } else {
        addstr(" had the jury, judge, and prosecution crying for freedom.");
        addjuice(g, 50, 1000); // That shit is legend
      }
    }
    await getKey();
    mvaddstrc(12, 1, lightGray, "The jury leaves to consider the case.");
    await getKey();
    erase();
    mvaddstrc(1, 1, lightGray, "The jury has returned from deliberations.");
    await getKey();

    //HUNG JURY
    if (defensepower == jury) {
      mvaddstrc(3, 1, yellow, "But they can't reach a verdict!");
      await getKey();

      //RE-TRY
      if (oneIn(2) || scarefactor >= 10 || g.confessions > 0) {
        mvaddstrc(5, 1, lightGray, "The case will be re-tried next month.");
        trialOutcome = TrialOutcome.retrial;

        await getKey();

        g.location = findSiteInSameCity(g.site?.city, SiteType.courthouse);
      }
      //NO RE-TRY
      else {
        mvaddstrc(
            5, 1, lightGray, "The prosecution declines to re-try the case.");
        trialOutcome = TrialOutcome.acquittal;

        await getKey();
      }
    }
    //ACQUITTAL!
    else if (defensepower > jury) {
      mvaddstrc(3, 1, lightGreen, "NOT GUILTY!");
      await getKey();

      trialOutcome = TrialOutcome.acquittal;

      // Juice sleeper
      if (defense == 4) addjuice(sleeperlawyer!, 10, 100);
      // Juice for self-defense
      if (defense == 1) addjuice(g, 10, 100);
    }
    //LENIENCE
    else //Guilty
    {
      // Juice for getting convicted of something :)
      addjuice(g, 25, 200);

      // Check for lenience; sleeper judge will always be merciful
      if (defensepower / 3 >= jury / 4 || sleeperjudge != null) {
        trialOutcome = TrialOutcome.lenience;
      } else {
        trialOutcome = TrialOutcome.guilty;
      }
    }
  }
  //GUILTY PLEA
  else {
    erase();
    mvaddstrc(1, 1, lightGray, "The court accepts the plea.");

    await getKey();

    // Check for lenience; sleeper judge will always be merciful
    if (sleeperjudge != null || oneIn(2)) {
      trialOutcome = TrialOutcome.lenience;
    } else {
      trialOutcome = TrialOutcome.guilty;
    }
  }

  if (trialOutcome == TrialOutcome.guilty ||
      trialOutcome == TrialOutcome.lenience) {
    await penalize(g, trialOutcome == TrialOutcome.lenience);
  }

  if (trialOutcome == TrialOutcome.acquittal) {
    if (g.sentence == 0) {
      mvaddstrc(5, 1, lightGreen, g.name);
      addstr(" is free!");
    } else {
      mvaddstrc(5, 1, lightGray, g.name);
      addstr(
          " will be returned to prison to resume ${g.gender.hisHer} earlier sentence.");
      g.sentence--;
      if (g.deathPenalty) {
        g.sentence = 3;
        mvaddstr(
            7, 1, "The execution is scheduled to occur three months from now.");
      }
    }
    await getKey();
  }

  //CLEAN UP LAW FLAGS
  for (var c in g.wantedForCrimes.entries) {
    g.wantedForCrimes[c.key] = 0;
  }
  //Clean up heat, confessions
  g.heat = 0;
  g.confessions = 0;
  //PLACE PRISONER
  if (g.sentence != 0) {
    imprison(g);
  } else {
    Armor clothes = Armor("ARMOR_CLOTHES");
    g.giveArmor(clothes, null);
  }
}

/* monthly - sentence a liberal */
Future<void> penalize(Creature g, bool lenient) async {
  mvaddstrc(3, 1, red, "GUILTY!");

  await getKey();

  int oldsentence = g.sentence;
  bool olddeathPenalty =
      g.deathPenalty && laws[Law.deathPenalty] != DeepAlignment.eliteLiberal;
  g.sentence = 0;
  g.deathPenalty = false;

  List<Crime> deathPenaltyCrimes = [
    Crime.murder,
    Crime.treason,
    if (laws[Law.flagBurning] == DeepAlignment.archConservative)
      Crime.flagBurning,
  ];

  if (!lenient &&
      (g.wantedForCrimes.entries
              .any((e) => deathPenaltyCrimes.contains(e.key) && e.value > 0) ||
          laws[Law.deathPenalty] == DeepAlignment.archConservative)) {
    g.deathPenalty = switch (laws[Law.deathPenalty]) {
      DeepAlignment.archConservative => true,
      DeepAlignment.conservative => !oneIn(3),
      DeepAlignment.moderate => oneIn(2),
      DeepAlignment.liberal => oneIn(5),
      _ => false,
    };
  }

  for (var e in g.wantedForCrimes.entries) {
    g.wantedForCrimes[e.key] = min(10, e.value);
  }

  //CALC TIME
  if (!g.deathPenalty) {
    void lifeOrTime(bool giveTime, int months, int life, Crime crime) {
      int count = g.wantedForCrimes[crime]!;
      if (count == 0) return;
      life = life * count;
      months = months * count;
      if (giveTime && g.sentence >= 0) {
        g.sentence += months;
      } else {
        g.sentence = min(g.sentence - life, -life);
      }
    }

    void time(int months, Crime crime) {
      if (g.sentence >= 0) {
        g.sentence += months * g.wantedForCrimes[crime]!;
      }
    }

    time(36 + lcsRandom(18), Crime.kidnapping);
    time(1 + lcsRandom(4), Crime.theft);
    time(6 + lcsRandom(7), Crime.grandTheftAuto);
    time(1 + lcsRandom(13), Crime.dataTheft);
    time(1 + lcsRandom(13), Crime.embezzlement);
    time(6 + lcsRandom(25), Crime.creditCardFraud);
    time(3 + lcsRandom(12), Crime.unlawfulBurial);
    time(1 + lcsRandom(6), Crime.prostitution);
    time(1, Crime.disturbingThePeace);
    time(1, Crime.publicNudity);
    time(1, Crime.harboring);
    time(12 + lcsRandom(100), Crime.racketeering);

    // How illegal is marijuana?
    time(
        switch (laws[Law.drugs]) {
          DeepAlignment.archConservative => 3 + lcsRandom(360),
          DeepAlignment.conservative => 3 + lcsRandom(120),
          DeepAlignment.moderate => 3 + lcsRandom(12),
          _ => 0,
        },
        Crime.drugDistribution);

    time(1, Crime.breakingAndEntering);
    time(60 + lcsRandom(181), Crime.terrorism);
    time(30 + lcsRandom(61), Crime.bankRobbery);
    time(30 + lcsRandom(61), Crime.juryTampering);
    time(30 + lcsRandom(61), Crime.aidingEscape);
    time(3 + lcsRandom(16), Crime.escapingPrison);
    time(1 + lcsRandom(1), Crime.resistingArrest);
    time(6 + lcsRandom(1), Crime.extortion);

    time(4 + lcsRandom(3), Crime.unlawfulSpeech);
    time(1, Crime.vandalism);
    time(12 + lcsRandom(12), Crime.arson);
    time(3 + lcsRandom(1), Crime.assault);
    switch (laws[Law.flagBurning]) {
      case DeepAlignment.archConservative:
        lifeOrTime(oneIn(2), 120 + lcsRandom(241), 1, Crime.flagBurning);
      case DeepAlignment.conservative:
        time(36, Crime.flagBurning);
      case DeepAlignment.moderate:
        time(1, Crime.flagBurning);
      default:
        break;
    }

    lifeOrTime(lcsRandom(4) - g.wantedForCrimes[Crime.murder]! > 0,
        120 + lcsRandom(241), 1, Crime.murder);
    lifeOrTime(true, 0, 1, Crime.treason);
    if (lenient && g.sentence != -1) g.sentence ~/= 2;
    if (lenient && g.sentence == -1) g.sentence = 240 + lcsRandom(120);
  }
  //LENIENCY AND CAPITAL PUNISHMENT DON'T MIX
  else if (g.deathPenalty && lenient) {
    g.deathPenalty = false;
    g.sentence = -1;
  }

  //MENTION LENIENCY
  if (lenient) {
    mvaddstrc(
        5, 1, lightGray, "During sentencing, the judge grants some leniency.");

    await getKey();
  }

  //MENTION SENTENCE
  if (olddeathPenalty) {
    g.deathPenalty = true;
    g.sentence = 3;
    mvaddstrc(7, 1, red, g.properName);
    addstr(", your previous death sentence will be carried out.");

    await getKey();

    mvaddstrc(9, 1, lightGray,
        "The execution is scheduled to occur three months from now.");

    await getKey();
  } else if (g.deathPenalty) {
    g.sentence = 3;
    setColor(yellow, background: darkRed);
    mvaddstr(7, 1, g.properName);
    addstr(", you are sentenced to DEATH!");

    await getKey();

    mvaddstrc(9, 1, lightGray,
        "The execution is scheduled to occur three months from now.");

    await getKey();
  }
  // Don't give a time-limited sentence if they already have a life sentence.
  else if ((g.sentence >= 0 && oldsentence < 0) ||
      (g.sentence == 0 && oldsentence > 0)) {
    g.sentence = oldsentence;
    mvaddstrc(7, 1, lightGray, g.properName);
    addstr(", the court sees no need to add to your existing sentence.");
    mvaddstr(
        8, 1, "You will be returned to prison to resume serving your time.");

    await getKey();
  } else if (g.sentence == 0) {
    mvaddstrc(7, 1, lightGray, g.properName);
    addstr(", you are sentenced to time served.  You are free to go.");

    await getKey();
  } else {
    if (g.sentence >= 36) g.sentence -= g.sentence % 12;

    mvaddstrc(7, 1, lightGray, g.properName);
    addstr(", you are sentenced to ");
    if (g.sentence > 1200) g.sentence ~/= -1200;

    if (g.sentence <= -1) {
      if (g.sentence < -1) {
        addstr("${-g.sentence} consecutive life terms in prison");

        // Don't bother saying this if the convicted already has one or
        // more life sentences. Makes the 'consecutively' and 'concurrently'
        // statements later easier to tack on.
        if (oldsentence >= 0) {
          addstr(".");

          await getKey();

          mvaddstr(9, 1, "Have a nice day, ");
          addstr(g.properName);
        }
      } else {
        addstr("life in prison");
      }
    } else if (g.sentence >= 36) {
      addstr("${g.sentence ~/ 12} years in prison");
    } else {
      addstr("${g.sentence} month");
      if (g.sentence > 1) addstr("s");
      addstr(" in prison");
    }

    // Mash together compatible sentences.
    if ((g.sentence > 0 && oldsentence > 0) ||
        (g.sentence < 0 && oldsentence < 0)) {
      addstr(",");
      move(8, 1);
      if (lenient) {
        if (oldsentence.abs() > g.sentence.abs()) {
          g.sentence = oldsentence;
        }
        addstr("to be served concurrently with your existing sentence.");
      } else {
        g.sentence += oldsentence;
        addstr("to be served consecutively with your existing sentence.");
      }
    } else {
      addstr(".");
    }

    await getKey();
  }
}
