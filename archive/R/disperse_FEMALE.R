###--- DISPERSE
disperse_FEMALE <- function(land,
                            rMove,
                            fishers,
                            dist_mov,
                            out,
                            torus){
  # UPDATED - now fishers checked at the start of the function to determine underlying patch condition
  # NEED TO UPDATE HAVE FISHERS PREFERNTIALLY MOVE TO PATCHES WITH MINIMUM 50% COVER - CAN'T DISPERSE IF UNSUITABLE MOVEMENT
  # Only want fishers without established territories to move
  # Assume female fisher can move ~35 km in a month, and that each pixel is 5.5 km in length or 7.8 km in diameter
  # For ease of calculations, assume a dist_mov of 1.0 is one pixel
  # This means that a female fisher can move between 5-6 pixels per month or 30-36 pixels in each time step
  # dist_mov relates to the number of cells (not quite right if fisher moving diagonally across a cell but works for our purposes)

  mHabitat <- raster2world(rMove[[1]]) # convert the underlying movement habitat layer to a NetLogo WorldMatrix object
  # if rMove is a RasterStack, defaults to first layer - this works for illustration purposes but will need to be conscious of it with dynamic simulations

  # fishers=tApr
  # dist_mov=1 ; out=TRUE; torus=TRUE

  # create a temporary data frame to use a simple 'case_when' to determine if fishers disperse or establish
  # for dispersing kits, keep dispersing if cell has unsuitable habitat (hab=0) or if occupied (dup = TRUE)
  tmp.fishers <- of(agents=fishers, var=c("who","breed","disperse","age"))
  fisher.cells <- patchHere(land, fishers)
  tmp.fishers$dup <- as.vector(duplicated(fisher.cells))
  tmp.fishers$hab <- of(land, agents=fisher.cells)
  tmp.fishers$hab[is.na(tmp.fishers$hab)] <- 0 # any NA habitat (i.e., outside of world is NOT suitable)

  # glimpse(tmp.fishers)
  whoDFishers <- tmp.fishers[tmp.fishers$disperse=="D" & tmp.fishers$age>0 | tmp.fishers$hab==0,]$who
  disperseInd <- turtle(fishers, who = whoDFishers) # fishers who are dispersing (i.e., kits)

  # only run if fishers
  if(NLcount(disperseInd)!=0){

    # The landscape is wrapped (torus = TRUE), meaning dispersing fishers re-enter
    # and the fishers can disperse outside of the landscape (out=TRUE)
    # have it so that fishers move only to neighbour with certain suitable habitat or movement value
    # written as a multi-step process:
    # 1. check neighbouring cells for suitable habitat and movement habitat values
    # 2. rank and order so that fishers will move first to neighbour with suitable habitat, then to neighbour with high movement habitat
    # 3. move fisher if neighbour is either suitable habitat or movement habitat value > 0.5
    # currently not considering if neighbour is occupied...does this matter for movement? might need to add in and rank as lower if occupied

    # fisher need to disperse to cells with >=0.5 movement habitat, choosing highest
    neighbour.cells <- as.data.frame(neighbors(mHabitat, disperseInd, nNeighbors=8))
    neighbour.cells$mHabitat <- of(mHabitat, as.matrix(neighbour.cells %>% select(-id)))
    neighbour.cells$Habitat <- of(land, as.matrix(neighbour.cells %>% select(-id)))
    mHab.neighbour.cells <- neighbour.cells %>% group_by(id) %>%                 # group by id
      mutate(moveTo = case_when(Habitat==1 ~ "SH",                               # create variable of SH (suitable habitat) or MH (movement habitat)
                                mHabitat >= 0.5 & Habitat==0 ~ "MH")) %>%
      arrange(desc(moveTo), desc(mHabitat), .by_group=TRUE) %>%               # arrange so SH, MH, then NA and within each group by highest movement habitat
      rowid_to_column() %>% mutate(mHab_ranks = min_rank(rowid))     # rank by habitat variable (SH, MH, NA) and quality of MH (>0.5 acceptable)

    fisher.cells <- as.data.frame(fisher.cells)
    fisher.cells$fisher <- "present"

    mHab.neighbour.cells <- mHab.neighbour.cells %>% left_join(fisher.cells, by=c("pxcor", "pycor"))
    move.cells <- mHab.neighbour.cells %>% filter(is.na(fisher)) %>% arrange(mHab_ranks) %>% group_by(id) %>% slice(1)

    disperseInd.who <- as.data.frame(disperseInd$who)
    colnames(disperseInd.who)[1] <- "who"
    disperseInd.who$id <- rownames(disperseInd.who)

    move.cells$who <- disperseInd.who$who[match(move.cells$id, disperseInd.who$id)]

    disperseInd.move.who <- turtle(disperseInd, who=move.cells$who) # fishers who can move (neighbouring cells with suitable habitat or movement habitat)
    disperseInd.moved <- moveTo(disperseInd.move.who, agents=as.matrix(move.cells %>% ungroup() %>% dplyr::select(pxcor, pycor)))


    # if any dispersing fishers have exited the worlds extent, remove them from the simulation
    # only necessary for torus = FALSE
    fisher.location <- as.data.frame(patchHere(land, fishers))
    fisher.location$who <- fishers$who
    # fisher.location %>% arrange(pxcor)
    out.of.bounds.fisher <- fisher.location[is.na(fisher.location$pxcor),]$who

    disperseInd.moved <- die(disperseInd.moved, who=out.of.bounds.fisher) # remove fishers who traveled outside worlds extent from dispersing object
    fishers <- die(fishers, who=out.of.bounds.fisher) # remove fishers who traveled outside worlds extent from main object

    # have the dispersing fishers move and update fisher data frame to note new locations
    valdisperseIndF <- of(agents=disperseInd.moved,
                          var=c("heading","xcor","ycor", "prevX","prevY"))
    fishers <- NLset(turtles = fishers, agents=turtle(fishers, who=disperseInd.moved$who),
                     var=c("heading","xcor","ycor","prevX","prevY"), val=valdisperseIndF)

    # recall that habitat = 1, unsuitable habitat = 0
    tmp.fishers <- tmp.fishers %>% mutate(move = case_when(disperse=="E" ~ "E",
                                                           (disperse=="D") & (dup==FALSE) & (hab==1) ~ "E",
                                                           TRUE ~ "D"))

    # workaround to remove juvenile duplicate on occupied territory...not sure how it even happens
    tmp.fishers <- tmp.fishers %>% mutate(move = case_when((breed=="juvenile") & (dup==TRUE) ~ "D",
                                                           TRUE ~ as.character(move)))
    # tmp.fishers %>% group_by(move) %>% dplyr::count(dup, hab)

    fishers <- NLset(turtles = fishers, agents=turtle(fishers, who=fishers$who),var="disperse",
                     val=tmp.fishers$move)
  }

  return(fishers)
}


# disperse_FEMALE(land=land,rMove=rMove[[1]],fishers=fishers,dist_mov=1.0,out=FALSE,torus=FALSE)

# plot(land)
# points(fishers, pch = disperseInd$shape, col = "black")
# points(disperseInd.moved, pch = disperseInd.moved$shape, col = "blue")
